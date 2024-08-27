const { graphql } = require('@octokit/graphql');
const core = require('@actions/core');
const exec = require('@actions/exec');
const fs = require('fs');
const path = require('path');

// Get inputs from GitHub Actions workflow
const GITHUB_TOKEN = core.getInput('github-token');
const CLI_VERSION = core.getInput('cli-version');
const EXECUTABLE_PATH = core.getInput('executable-path');
const PIP_INSTALL = core.getInput('pip-install') === 'true';

// Configure authenticated GraphQL client
const graphqlWithAuth = graphql.defaults({
  headers: {
    authorization: `token ${GITHUB_TOKEN}`,
  },
});

// Define the Github repository for CLI
const REPOSITORY = `repository(owner: "cloudsmith-io", name: "cloudsmith-cli")`;

// Normalize version for GraphQL queries
function normalizeVersionForGraphQL(version) {
  return version.startsWith('v') ? version : `v${version}`;
}

// Normalize version for pip installation
function normalizeVersionForPip(version) {
  return version.startsWith('v') ? version.slice(1) : version;
}

// Download the latest release of the CLI
async function downloadLatestRelease() {
  try {
    const query = `
      query {
        ${REPOSITORY} {
          latestRelease {
            releaseAssets(first: 1) {
              nodes {
                name
                downloadUrl
              }
            }
          }
        }
      }
    `;

    const response = await graphqlWithAuth(query);
    const downloadUrl = response.repository.latestRelease.releaseAssets.nodes[0].downloadUrl;
    await downloadFile(downloadUrl, EXECUTABLE_PATH);
  } catch (error) {
    core.setFailed(`Failed to download the latest release: ${error.message}`);
  }
}

// Download a specific release of the CLI by version
async function downloadSpecificRelease(version) {
  try {
    const normalizedVersion = normalizeVersionForGraphQL(version);
    const query = `
      query ($tagName: String!) {
        ${REPOSITORY} {
          release(tagName: $tagName) {
            releaseAssets(first: 1) {
              nodes {
                name
                downloadUrl
              }
            }
          }
        }
      }
    `;

    const variables = {
      tagName: normalizedVersion,
    };

    const response = await graphqlWithAuth(query, variables);
    const downloadUrl = response.repository.release.releaseAssets.nodes[0].downloadUrl;
    await downloadFile(downloadUrl, EXECUTABLE_PATH);
  } catch (error) {
    core.setFailed(`Failed to download the specific release (${version}): ${error.message}`);
  }
}

// Download a file from a URL and save it to the specified path
async function downloadFile(url, outputPath) {
  try {
    const fileName = path.basename(url);
    const filePath = path.join(outputPath, fileName);
    const writer = fs.createWriteStream(filePath);

    const response = await fetch(url);
    response.body.pipe(writer);

    return new Promise((resolve, reject) => {
      writer.on('finish', resolve);
      writer.on('error', reject);
    });
  } catch (error) {
    core.setFailed(`Failed to download the file from ${url}: ${error.message}`);
  }
}

// Install the CLI either via pip or by downloading the release
async function installCli() {
  try {
    if (PIP_INSTALL) {
      await installCliViaPip();
    } else if (CLI_VERSION && CLI_VERSION !== 'none') {
      await downloadSpecificRelease(CLI_VERSION);
    } else {
      await downloadLatestRelease();
    }
  } catch (error) {
    core.setFailed(`Failed to install the CLI: ${error.message}`);
  }
}

// Install the CLI via pip
async function installCliViaPip() {
  try {
    const normalizedVersion = normalizeVersionForPip(CLI_VERSION);
    const cliPackage = CLI_VERSION && CLI_VERSION !== 'none' ? `cloudsmith-cli==${normalizedVersion}` : 'cloudsmith-cli';
    await exec.exec('pip', ['install', cliPackage]);
  } catch (error) {
    core.setFailed(`Failed to install the CLI via pip: ${error.message}`);
  }
}

// Export functions for external use
module.exports = {
  downloadLatestRelease,
  downloadSpecificRelease,
  downloadFile,
  installCli,
  installCliViaPip,
};