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
    const headers = {};
    if (error.response.headers && typeof error.response.headers.forEach === 'function') {
      error.response.headers.forEach((value, key) => {
        headers[key] = value;
      });
    }
    core.error(JSON.stringify(headers, null, 2));
    core.error("Response Body:");
    core.error(JSON.stringify(error.response.data, null, 2));
  } else if (error.request) {
    core.error("No response received from server");
    core.error("Request details:");
    core.error(`  Method: ${error.request.method || "POST"}`);
    core.error(`  URL: ${error.request.url}`);
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
        const delayMs = RETRY_DELAY_MS * Math.pow(2, attempt);
        const jitter = Math.random() * delayMs * 0.1;
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
 * Makes an HTTP request using native fetch with timeout support.
 *
 * @param {string} url - The URL to request.
 * @param {object} options - Fetch options (method, headers, body, etc.).
 * @param {number} timeout - Timeout in milliseconds.
 * @returns {Promise<{status: number, statusText: string, data: any, headers: Headers}>}
 */
async function fetchWithTimeout(url, options = {}, timeout = REQUEST_TIMEOUT_MS) {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeout);

  try {
    const response = await fetch(url, {
      ...options,
      signal: controller.signal,
    });

    let data;
    const contentType = response.headers.get("content-type");
    if (contentType && contentType.includes("application/json")) {
      data = await response.json();
    } else {
      data = await response.text();
    }

    if (!response.ok) {
      const error = new Error(`HTTP ${response.status}: ${response.statusText}`);
      error.response = {
        status: response.status,
        statusText: response.statusText,
        headers: response.headers,
        data,
      };
      throw error;
    }

    return {
      status: response.status,
      statusText: response.statusText,
      data,
      headers: response.headers,
    };
  } catch (error) {
    if (error.name === "AbortError") {
      const timeoutError = new Error(`Request timeout after ${timeout}ms`);
      timeoutError.code = "ETIMEDOUT";
      throw timeoutError;
    }
    throw error;
  } finally {
    clearTimeout(timeoutId);
  }
}

/**
 * Authenticates with Cloudsmith using OIDC and validates the token.
 *
 * @param {string} orgName - The organization name.
 * @param {string} serviceAccountSlug - The service account slug.
 * @param {string} apiHost - The API host to connect to (optional).
 * @param {number} retryAttempts - Number of retry attempts for authentication (0-10).
 * @param {boolean} validateToken - Whether to validate the token after authentication (default: true).
 * @param {string} oidcAudience - The audience to request when retrieving the GitHub OIDC token.
 */
async function authenticate(
  orgName,
  serviceAccountSlug,
  apiHost,
  retryAttempts = 3,
  validateToken = true,
  oidcAudience = '',
) {
  const baseUrl = `https://${apiHost || DEFAULT_API_HOST}`;
  let idToken;
  let token;

  try {
    core.info(
      `Attempting OIDC authentication with ${retryAttempts} retry attempts...`,
    );

    // Retrieve the OIDC ID token from GitHub Actions using configurable audience
    const audience = oidcAudience.trim();
    core.info(`Requesting GitHub OIDC token for audience: ${audience}`);
    idToken = await core.getIDToken(audience);

    // Authenticate with Cloudsmith using OIDC token
    await retryWithDelay(
      async () => {
        const response = await fetchWithTimeout(
          `${baseUrl}/openid/${orgName}/`,
          {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              oidc_token: idToken,
              service_slug: serviceAccountSlug,
            }),
          },
          REQUEST_TIMEOUT_MS,
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
        core.setOutput('oidc-token', token);
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
  const response = await fetchWithTimeout(
    `${baseUrl}/v1/user/self/`,
    {
      method: "GET",
      headers: {
        accept: "application/json",
        Authorization: `Bearer ${token}`,
      },
    },
    REQUEST_TIMEOUT_MS,
  );

  const data = response.data;
  core.info(`User has successfully authenticated as ${data.name}.`);
}

module.exports = { authenticate };
