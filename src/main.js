const core = require('@actions/core');
const oidcAuth = require('./oidc-auth');
const { installCli } = require('./download-cli');

async function run() {
  try {
    // Get inputs from GitHub Actions workflow
    const orgName = core.getInput('oidc-namespace');
    const serviceAccountSlug = core.getInput('oidc-service-slug');
    const apiKey = core.getInput('api-key');

    // Authenticate using OIDC if inputs are provided, otherwise use API key
    if (orgName && serviceAccountSlug) {
      await oidcAuth.authenticate(orgName, serviceAccountSlug);
    } else if (apiKey) {
      core.exportVariable("CLOUDSMITH_API_KEY", apiKey);
      core.info("Using provided API key for authentication.");
    } else {
      throw new Error("Either OIDC inputs or API key must be provided for authentication.");
    }

    // Install the CLI
    await installCli();
  } catch (error) {
    core.setFailed(`Action failed: ${error.message}`);
  }
}

run();