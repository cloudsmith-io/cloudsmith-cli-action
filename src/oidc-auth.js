const axios = require("axios");
const core = require("@actions/core");
const fetch = require("node-fetch");

/**
 * Authenticates with Cloudsmith using OIDC and validates the token.
 *
 * @param {string} orgName - The organization name.
 * @param {string} serviceAccountSlug - The service account slug.
 */
async function authenticate(orgName, serviceAccountSlug) {
  try {
    // Retrieve the OIDC ID token from GitHub Actions
    const idToken = await core.getIDToken("api://AzureADTokenExchange");

    // Send a POST request to Cloudsmith API to authenticate using the OIDC token
    const response = await axios.post(
      `https://api.cloudsmith.io/openid/${orgName}/`,
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
    if (response.status !== 200) {
      throw new Error(`Failed to authenticate: ${response.statusText}`);
    }

    // Extract the API token from the response
    const token = response.data.token;

    // Export the API token as an environment variable
    core.exportVariable("CLOUDSMITH_API_KEY", token);
    core.info(
      "Authenticated successfully with OIDC and saved API key to environment variable."
    );

    // Validate the token to ensure it is correct
    await validateToken(token);
  } catch (error) {
    // Set the GitHub Action as failed if any error occurs
    core.setFailed(`OIDC authentication failed: ${error.message}`);
  }
}

/**
 * Validates the Cloudsmith API token by making a request to the user endpoint.
 *
 * @param {string} token - The Cloudsmith API token.
 */
async function validateToken(token) {
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
      "https://api.cloudsmith.io/v1/user/self/",
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
