const core = require('@actions/core');
const oidcAuth = require('./oidc-auth');
const { installCli } = require('./download-cli');
const { createConfigFile } = require('./create-config-file');

async function run() {
  try {
    // Get inputs from GitHub Actions workflow
    const orgName = core.getInput('oidc-namespace');
    const serviceAccountSlug = core.getInput('oidc-service-slug');
    const apiKey = core.getInput('api-key');
    const oidcAuthRetry = Math.min(Math.max(parseInt(core.getInput('oidc-auth-retry') || '3', 10), 0), 10);
    
    // Cloudsmith CLI optional inputs
    const apiHost = core.getInput('api-host');
    const apiProxy = core.getInput('api-proxy');
    const apiSslVerify = core.getInput('api-ssl-verify');
    const apiUserAgent = core.getInput('api-user-agent');

    // Create config file for Cloudsmith CLI only if any of the optional inputs are provided
    if (apiHost || apiProxy || apiSslVerify || apiUserAgent) {
      createConfigFile(apiHost, apiProxy, apiSslVerify, apiUserAgent);
    }

    // Authenticate based on the provided inputs
    if (apiKey) {
      core.exportVariable("CLOUDSMITH_API_KEY", apiKey);
      core.info("Using provided API key for authentication.");
    } else if (orgName && serviceAccountSlug) {

      // check if environment variable "ACTIONS_ID_TOKEN_REQUEST_URL" is set
      const token = process.env.ACTIONS_ID_TOKEN_REQUEST_URL;
      core.info(`ACTIONS_ID_TOKEN_REQUEST_URL: ${token}`);
      if (!token) {
        throw new Error("Environment variable ACTIONS_ID_TOKEN_REQUEST_URL is not set. Did you add the permission 'id-token: write' to your workflow?");
      } 

      await oidcAuth.authenticate(orgName, serviceAccountSlug, apiHost, oidcAuthRetry);
    } else {
      throw new Error("Either API key or OIDC inputs (namespace and service account slug) must be provided for authentication.");
    }

    // Install the CLI only if oidc-auth-only is false
    const oidcAuthOnly = core.getBooleanInput('oidc-auth-only');
    if (!oidcAuthOnly) {
      await installCli();
    }
  
  } catch (error) {
    core.setFailed(`Action failed: ${error.message}`);
  }
}

run();
