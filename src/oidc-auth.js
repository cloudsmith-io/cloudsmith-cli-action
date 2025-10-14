const axios = require("axios");
const core = require("@actions/core");

const DEFAULT_API_HOST = "api.cloudsmith.io";
const RETRY_DELAY_MS = 5000; // 5 seconds delay between attempts
const REQUEST_TIMEOUT_MS = 30000;

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

function logHttpError(error, context = "") {
  const header = context ? `=== ${context} ===` : "=== HTTP Error ===";
  core.error(header);
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

  if (error.stack) {
    core.error("Stack Trace:");
    core.error(error.stack);
  }

  core.error("=========================================");
}

function logDetailedError(error, idToken = null) {
  logHttpError(error, "OIDC Authentication Error Details");

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
    core.error("=========================================");
  }
}

async function retryWithDelay(fn, retries, operationType, idToken = null) {
  let lastError;
  for (let attempt = 1; attempt <= retries; attempt++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error;

      core.error(`${operationType} attempt ${attempt} failed`);
      if (idToken) {
        logDetailedError(error, idToken);
      } else {
        logHttpError(error, `${operationType} Error`);
      }

      const isRetryable = !error.response || error.response.status >= 500;

      if (!isRetryable) {
        core.error(
          `Received 4xx error (${error.response?.status}), not retrying`,
        );
        throw lastError;
      }

      if (attempt < retries) {
        const delayMs = RETRY_DELAY_MS * Math.pow(2, attempt - 1);
        const jitter = Math.random() * 1000;
        const totalDelay = delayMs + jitter;

        core.info(
          `${operationType} attempt ${attempt} failed, retrying in ${(totalDelay / 1000).toFixed(1)} seconds...`,
        );
        await new Promise((resolve) => setTimeout(resolve, totalDelay));
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
 * @param {boolean} validateToken - Whether to validate the token after authentication (default: true).
 */
async function authenticate(
  orgName,
  serviceAccountSlug,
  apiHost,
  retryAttempts = 3,
  validateToken = true,
) {
  const baseUrl = `https://${apiHost || DEFAULT_API_HOST}`;
  let idToken;
  let token;

  try {
    core.info(
      `Attempting OIDC authentication with ${retryAttempts} retry attempts...`,
    );

    // Retrieve the OIDC ID token from GitHub Actions
    idToken = await core.getIDToken("api://AzureADTokenExchange");

    // Authenticate with Cloudsmith using OIDC token
    await retryWithDelay(
      async () => {
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
            timeout: REQUEST_TIMEOUT_MS,
          },
        );

        if (response.status !== 200 && response.status !== 201) {
          throw new Error(`Failed to authenticate: ${response.statusText}`);
        }

        token = response.data.token;

        if (!token || typeof token !== "string" || token.trim() === "") {
          const error = new Error(
            "Cloudsmith returned an empty or invalid token in the response",
          );
          error.response = response;
          throw error;
        }

        core.exportVariable("CLOUDSMITH_API_KEY", token);
        core.info(
          "Authenticated successfully with OIDC and saved JWT (token) to `CLOUDSMITH_API_KEY` environment variable.",
        );
      },
      retryAttempts,
      "OIDC authentication",
      idToken,
    );

    // Optionally validate the token to ensure it is correct
    if (validateToken) {
      core.info("Validating API token...");
      await retryWithDelay(
        async () => {
          await validateApiToken(token, baseUrl);
        },
        retryAttempts,
        "Token validation",
      );
    }
  } catch (error) {
    const operation = token ? "Token validation" : "OIDC authentication";
    core.setFailed(`${operation} failed: ${error.message}`);
  }
}

/**
 * Validates the Cloudsmith API token by making a request to the user endpoint.
 *
 * @param {string} token - The Cloudsmith API token.
 * @param {string} baseUrl - The base URL for the API.
 */
async function validateApiToken(token, baseUrl) {
  const response = await axios.get(`${baseUrl}/v1/user/self/`, {
    headers: {
      accept: "application/json",
      "X-Api-Key": token,
    },
    timeout: REQUEST_TIMEOUT_MS,
  });

  const data = response.data;
  core.info(`User has successfully authenticated as ${data.name}.`);
}

module.exports = { authenticate };
