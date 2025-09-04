const axios = require("axios");
const core = require("@actions/core");

const DEFAULT_API_HOST = 'api.cloudsmith.io';
const RETRY_DELAY_MS = 5000; // 5 seconds delay between attempts

async function retryWithDelay(fn, retries) {
  let lastError;
  for (let attempt = 1; attempt <= retries; attempt++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error;
      if (attempt < retries) {
        core.info(`OIDC authentication attempt ${attempt} failed, retrying in ${RETRY_DELAY_MS/1000} seconds...`);
        await new Promise(resolve => setTimeout(resolve, RETRY_DELAY_MS));
      }
    }
  }
  throw lastError;
}

/**
 * Authenticates with Cloudsmith using OIDC and validates the token.
 *
 * @param {string} orgName - The organization name.
 * @param {string} serviceAccountSlug - The service account slug.
 * @param {string} apiHost - The API host to connect to (optional).
 * @param {number} retryAttempts - Number of retry attempts for authentication (0-10).
 */
async function authenticate(orgName, serviceAccountSlug, apiHost, retryAttempts = 3) {
  try {
    core.info(`Attempting OIDC authentication with ${retryAttempts} retry attempts...`);

    await retryWithDelay(async () => {
      // Retrieve the OIDC ID token from GitHub Actions
      const idToken = await core.getIDToken("api://AzureADTokenExchange");

      // Use the provided apiHost or default to api.cloudsmith.io
      const baseUrl = `https://${apiHost || DEFAULT_API_HOST}`;

      // Send a POST request to Cloudsmith API to authenticate using the OIDC token
      const response = await axios.post(
        `${baseUrl}/openid/${orgName}/`,
        {
          oidc_token: idToken,
          service_slug: serviceAccountSlug,
        },
        {
          headers: {
            "Content-Type": "application/json",
          },
        }
      );

      // Check if the authentication was successful
      if (response.status !== 200 && response.status !== 201) {
        throw new Error(`Failed to authenticate: ${response.statusText}`);
      }

      // Extract the API token from the response
      const token = response.data.token;

      // Export the API token as an environment variable
      core.exportVariable("CLOUDSMITH_API_KEY", token);
      // Set the token as an output
      core.setOutput('oidc-token', token);
      core.info(
        "Authenticated successfully with OIDC and saved JWT (token) to `CLOUDSMITH_API_KEY` environment variable."
      );

      // Validate the token to ensure it is correct
      await validateToken(token, baseUrl);
    }, retryAttempts);
  } catch (error) {
    // Set the GitHub Action as failed if any error occurs
    core.setFailed(`OIDC authentication failed: ${error.message}`);
  }
}

/**
 * Validates the Cloudsmith API token by making a request to the user endpoint.
 *
 * @param {string} token - The Cloudsmith API token.
 * @param {string} baseUrl - The base URL for the API.
 */
async function validateToken(token, baseUrl) {
  const options = {
    method: "GET",
    headers: {
      accept: "application/json",
      "X-Api-Key": token,
    },
  };

  try {
    // Send a GET request to Cloudsmith API to validate the token
    const response = await fetch(
      `${baseUrl}/v1/user/self/`,
      options
    );

    // Check if the token validation was successful
    if (!response.ok) {
      throw new Error(`Failed to validate token: ${response.statusText}`);
    }

    // Parse the response data
    const data = await response.json();
    core.info(`User has successfully authenticated as ${data.name}.`);
  } catch (error) {
    // Set the GitHub Action as failed if any error occurs during token validation
    core.setFailed(`Token validation failed: ${error.message}`);
  }
}

module.exports = { authenticate };
