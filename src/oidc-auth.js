const axios = require("axios");
const core = require("@actions/core");

const DEFAULT_API_HOST = 'api.cloudsmith.io';

/**
 * Authenticates with Cloudsmith using OIDC and validates the token.
 *
 * @param {string} orgName - The organization name.
 * @param {string} serviceAccountSlug - The service account slug.
 * @param {string} apiHost - The API host to connect to (optional).
 */
async function authenticate(orgName, serviceAccountSlug, apiHost) {
  try {
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
    core.info(
      "Authenticated successfully with OIDC and saved JWT (token) to `CLOUDSMITH_API_KEY` environment variable."
    );

    // Validate the token to ensure it is correct
    await validateToken(token, baseUrl);
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
