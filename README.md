# Cloudsmith CLI Install Action

[![Test Status](https://github.com/cloudsmith-io/cloudsmith-cli-action/actions/workflows/test_install.yml/badge.svg)](https://github.com/cloudsmith-io/cloudsmith-cli-action/actions/workflows/test_install.yml)
[![GitHub Marketplace](https://img.shields.io/badge/Marketplace-Cloudsmith%20CLI%20Install-blue.svg?colorA=24292e&colorB=0366d6&style=flat&longCache=true&logo=github)](https://github.com/marketplace/actions/cloudsmith-cli-install-action)
[![Node.js Version](https://img.shields.io/badge/node-24-brightgreen.svg)](https://nodejs.org/)
[![License](https://img.shields.io/github/license/cloudsmith-io/cloudsmith-cli-action.svg)](LICENSE)
[![Version](https://img.shields.io/github/v/release/cloudsmith-io/cloudsmith-cli-action.svg)](https://github.com/cloudsmith-io/cloudsmith-cli-action/releases)

This GitHub Action installs the Cloudsmith CLI and pre-authenticates it using OIDC or API Key. 🚀

**⚠️ Notice:** The `@v2` of the cloudsmith cli action now runs on Node24 as a minimum requirement. If you still rely on Node20, please use `@v1` and plan for future migration.

**⚠️ Notice:** If you are running on self-hosted runners, Python version 3.9 or higher is required. Please ensure your runner meets this requirement to avoid any issues. We recommend using [setup-python](https://github.com/actions/setup-python) action for installing Python. 🐍

## Inputs

### Authentication & Installation

| Input                  | Description | Required | Default |
|------------------------|-------------|----------|---------|
| `cli-version` | Specific version of the Cloudsmith CLI to install | No | Latest |
| `api-key` | API Key for Cloudsmith authentication | No | - |
| `oidc-namespace` | Cloudsmith organisation/namespace for OIDC | No | - |
| `oidc-service-slug` | Cloudsmith service account slug for OIDC | No | - |
| `oidc-auth-only` | Only perform OIDC authentication without installing the CLI | No | `false` |
| `oidc-auth-retry` | Number of retry attempts for OIDC authentication (0-10), 5 seconds delay between retries | No | `3` |
| `oidc-audience` | Audience to request when retrieving the GitHub OIDC token. Use `https://github.com/<org-name>` for standard GitHub audience | No | `api://AzureADTokenExchange` |
| `pip-install` | Install the Cloudsmith CLI via pip | No | - |
| `executable-path` | Path to the Cloudsmith CLI executable | No | `GITHUB_WORKSPACE/bin/` |

### CLI Configuration

See [CLI configuration documentation](https://github.com/cloudsmith-io/cloudsmith-cli?tab=readme-ov-file#non-credentials-configini) for more details.

| Input                  | Description | Required | Default |
|------------------------|-------------|----------|---------|
| `api-host` | API Host for Cloudsmith | No | - |
| `api-proxy` | API Proxy for Cloudsmith | No | - |
| `api-ssl-verify` | Verify SSL certificates for Cloudsmith API | No | - |
| `api-user-agent` | User Agent for Cloudsmith API | No | - | 

## Example Usage with OIDC

Cloudsmith OIDC [documentation](https://docs.cloudsmith.com/authentication/openid-connect)

```yaml
uses: cloudsmith-io/cloudsmith-cli-action@v2
with:
  oidc-namespace: 'your-oidc-namespace'
  oidc-service-slug: 'your-service-account-slug'
```

## Example Usage with API Key

Personal API Key can be found [here](https://cloudsmith.io/user/settings/api/). For CI-CD deployments we recommend using [Service Accounts](https://docs.cloudsmith.com/accounts-and-teams/service-accounts).

```yaml
uses: cloudsmith-io/cloudsmith-cli-action@v2
with:
  api-key: 'your-api-key'
```

## Example Usage with OIDC Authentication Only

If you only need to authenticate with Cloudsmith's API without installing the CLI:

```yaml
uses: cloudsmith-io/cloudsmith-cli-action@v2
with:
  oidc-namespace: 'your-oidc-namespace'
  oidc-service-slug: 'your-service-account-slug'
  oidc-auth-only: 'true'
```

This will:
- Perform OIDC authentication
- Set the OIDC token as `CLOUDSMITH_API_KEY` environment variable
- Skip CLI installation

## Cloudsmith CLI Commands

Full CLI feature list can be found [here](https://github.com/cloudsmith-io/cloudsmith-cli?tab=readme-ov-file#features)


### Publish a package

For all supported package formats and upload commands please visit our [Supported Formats](https://docs.cloudsmith.com/formats) page.

```yaml
name: Publish Python Package

on:
  push:
    branches:
      - main
permissions:
  id-token: write
  contents: read
jobs:
  publish:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Install Cloudsmith CLI
        uses: cloudsmith-io/cloudsmith-cli-action@v2
        with:
          oidc-namespace: 'your-oidc-namespace'
          oidc-service-slug: 'your-service-account-slug'

      - name: Push package to Cloudsmith
        run: |
          cloudsmith push python your-namespace/your-repository dist/*.tar.gz
```
## Contribution

Please check our [CONTRIBUTION](CONTRIBUTION.md) doc for more information. 🤝

## License

This project is licensed under the MIT License - see the LICENSE file for details. 📄

## Support

If you have any questions or need further assistance, please open an issue on GitHub. We're here to help! Alternatively, you can contact us at [support.cloudsmith.com](https://support.cloudsmith.com/).

