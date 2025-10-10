const axios = require("axios");
const core = require("@actions/core");

const DEFAULT_API_HOST = "api.cloudsmith.io";
const RETRY_DELAY_MS = 5000; // 5 seconds delay between attempts

function decodeJWT(token) {
  try {
    const parts = token.split(".");
    if (parts.length !== 3) {
      return { error: "Invalid JWT format" };
    }

    const decodeBase64Url = (str) => {
      let base64 = str.replace(/-/g, "+").replace(/_/g, "/");
      const padding = base64.length % 4;
      if (padding > 0) {
        base64 += "=".repeat(4 - padding);
      }
      return Buffer.from(base64, "base64").toString();
    };

    const header = JSON.parse(decodeBase64Url(parts[0]));
    const payload = JSON.parse(decodeBase64Url(parts[1]));

    return { header, payload };
  } catch (error) {
    return { error: `Failed to decode JWT: ${error.message}` };
  }
}

function logDetailedError(error, idToken = null) {
  core.error("=== OIDC Authentication Error Details ===");
  core.error(`Error Message: ${error.message}`);

  if (error.code) {
    core.error(`Error Code: ${error.code}`);
  }

  if (error.response) {
    core.error(`HTTP Status Code: ${error.response.status}`);
    core.error(`HTTP Status Text: ${error.response.statusText}`);
    core.error("Response Headers:");
    core.error(JSON.stringify(error.response.headers, null, 2));
    core.error("Response Body:");
    core.error(JSON.stringify(error.response.data, null, 2));
  } else if (error.request) {
    core.error("No response received from server");
    core.error("Request details:");
    core.error(`  Method: ${error.request.method || "POST"}`);
    core.error(`  Path: ${error.request.path}`);
    core.error(`  Host: ${error.request.host}`);
  }

  if (idToken) {
    core.error("=== JWT Token Information ===");
    const decoded = decodeJWT(idToken);

    if (decoded.error) {
      core.error(decoded.error);
    } else {
      core.error("JWT Headers:");
      core.error(JSON.stringify(decoded.header, null, 2));
      core.error("JWT Claims (Payload):");
      core.error(JSON.stringify(decoded.payload, null, 2));
    }
  }

  if (error.stack) {
    core.error("Stack Trace:");
    core.error(error.stack);
  }

  core.error("=========================================");
}

async function retryWithDelay(fn, retries, idToken) {
  let lastError;
  for (let attempt = 1; attempt <= retries; attempt++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error;
      core.error(`OIDC authentication attempt ${attempt} failed`);
      logDetailedError(error, idToken);

      if (attempt < retries) {
        core.info(
          `OIDC authentication attempt ${attempt} failed, retrying in ${RETRY_DELAY_MS / 1000} seconds...`,
        );
        await new Promise((resolve) => setTimeout(resolve, RETRY_DELAY_MS));
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
async function authenticate(
  orgName,
  serviceAccountSlug,
  apiHost,
  retryAttempts = 3,
) {
  let idToken;

  try {
    core.info(
      `Attempting OIDC authentication with ${retryAttempts} retry attempts...`,
    );

    // Retrieve the OIDC ID token from GitHub Actions
    idToken = await core.getIDToken("api://AzureADTokenExchange");

    // Use the provided apiHost or default to api.cloudsmith.io
    await retryWithDelay(
      async () => {
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
          },
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
          "Authenticated successfully with OIDC and saved JWT (token) to `CLOUDSMITH_API_KEY` environment variable.",
        );

        // Validate the token to ensure it is correct
        await validateToken(token, baseUrl);
      },
      retryAttempts,
      idToken,
    );
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
    const response = await fetch(`${baseUrl}/v1/user/self/`, options);

    // Check if the token validation was successful
    if (!response.ok) {
      const responseBody = await response.text();
      core.error("=== Token Validation Error ===");
      core.error(`HTTP Status Code: ${response.status}`);
      core.error(`HTTP Status Text: ${response.statusText}`);
      core.error("Response Body:");
      core.error(responseBody);
      core.error("==============================");
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
