const core = require('@actions/core');
const exec = require('@actions/exec');
const fs = require('fs');
const path = require('path');
const fetch = require('node-fetch');

// Get inputs from GitHub Actions workflow
const CLI_VERSION = core.getInput('cli-version');
const EXECUTABLE_PATH = core.getInput('executable-path') || process.env.GITHUB_WORKSPACE;
const PIP_INSTALL = core.getInput('pip-install') === 'true';

// Normalize version for pip installation and direct download
function normalizeVersion(version) {
  return version.startsWith('v') ? version.slice(1) : version;
}

// Download the latest release of the CLI
async function downloadLatestRelease() {
  try {
    const downloadUrl = 'https://dl.cloudsmith.io/public/bart-demo-org/cloudsmith-cli-zipapp/raw/names/cloudsmith-cli/versions/latest/cloudsmith.pyz';
    await downloadFile(downloadUrl, EXECUTABLE_PATH);
  } catch (error) {
    core.setFailed(`Failed to download the latest release: ${error.message}`);
  }
}

// Download a specific release of the CLI by version
async function downloadSpecificRelease(version) {
  try {
    const normalizedVersion = normalizeVersion(version);
    const downloadUrl = `https://dl.cloudsmith.io/public/bart-demo-org/cloudsmith-cli-zipapp/raw/names/cloudsmith-cli/versions/${normalizedVersion}/cloudsmith.pyz`;
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

    // Ensure the directory exists
    fs.mkdirSync(path.dirname(filePath), { recursive: true });

    const writer = fs.createWriteStream(filePath);

    const response = await fetch(url);
    if (!response.ok) {
      throw new Error(`Failed to fetch ${url}: ${response.statusText}`);
    }
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
    const normalizedVersion = normalizeVersion(CLI_VERSION);
    const cliPackage = CLI_VERSION && CLI_VERSION !== 'none' ? `cloudsmith-cli==${normalizedVersion}` : 'cloudsmith-cli';
    await exec.exec('pip', ['install', cliPackage], '--index-url=https://dl.cloudsmith.io/public/cloudsmith/cli/python/simple/');
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