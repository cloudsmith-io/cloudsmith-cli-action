const core = require('@actions/core');
const exec = require('@actions/exec');
const fs = require('fs');
const path = require('path');
const fetch = require('node-fetch').default;
const os = require('os');

// Get inputs from GitHub Actions workflow
const CLI_VERSION = core.getInput('cli-version');
const EXECUTABLE_PATH = core.getInput('executable-path') || path.join(process.env.GITHUB_WORKSPACE, 'bin', 'cloudsmith');
const PIP_INSTALL = core.getInput('pip-install') === 'true';

// Ensure the executable directory exists
fs.mkdirSync(path.dirname(EXECUTABLE_PATH), { recursive: true });

// Helper function to download a file and set permissions
async function downloadFile(url, dest) {
  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`Failed to fetch ${url}: ${res.statusText}`);
  }
  const fileStream = fs.createWriteStream(dest);
  await new Promise((resolve, reject) => {
    res.body.pipe(fileStream);
    res.body.on('error', reject);
    fileStream.on('finish', resolve);
  });
  fs.chmodSync(dest, '755');
}

// Helper function to add path and create Windows batch script if needed
function addPathAndCreateBatchScript() {
  core.addPath(path.dirname(EXECUTABLE_PATH));
  if (os.platform() === 'win32') {
    const batFilePath = path.join(path.dirname(EXECUTABLE_PATH), 'cloudsmith.bat');
    const content = `@echo off\npython ${EXECUTABLE_PATH} %*`;
    fs.writeFileSync(batFilePath, content);
    core.addPath(path.dirname(batFilePath));
  }
}

// Download the latest release of the CLI
async function downloadLatestRelease() {
  try {
    const downloadUrl = 'https://dl.cloudsmith.io/public/bart-demo-org/cloudsmith-cli-zipapp/raw/names/cloudsmith-cli/versions/latest/cloudsmith.pyz';
    await downloadFile(downloadUrl, EXECUTABLE_PATH);
    addPathAndCreateBatchScript();
  } catch (error) {
    core.setFailed(`Failed to download the latest release: ${error.message}`);
  }
}

// Download a specific release of the CLI by version
async function downloadSpecificRelease(version) {
  try {
    const downloadUrl = `https://dl.cloudsmith.io/public/bart-demo-org/cloudsmith-cli-zipapp/raw/names/cloudsmith-cli/versions/${version}/cloudsmith.pyz`;
    await downloadFile(downloadUrl, EXECUTABLE_PATH);
    addPathAndCreateBatchScript();
  } catch (error) {
    core.setFailed(`Failed to download the specific release: ${error.message}`);
  }
}

// Install the CLI via pip
async function installCliViaPip() {
  try {
    const cliPackage = CLI_VERSION && CLI_VERSION !== 'none' ? `cloudsmith-cli==${CLI_VERSION}` : 'cloudsmith-cli';
    await exec.exec('pip', ['install', cliPackage], '--index-url=https://dl.cloudsmith.io/public/cloudsmith/cli/python/simple/');
  } catch (error) {
    core.setFailed(`Failed to install the CLI via pip: ${error.message}`);
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

// Export functions for external use
module.exports = {
  downloadLatestRelease,
  downloadSpecificRelease,
  downloadFile,
  installCli,
  installCliViaPip,
};