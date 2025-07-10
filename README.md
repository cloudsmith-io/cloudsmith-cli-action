# Cloudsmith CLI Install Action

This GitHub Action installs the Cloudsmith CLI and pre-authenticates it using OIDC or API Key. 🚀

> **⚠️ Notice:** If you are running on self-hosted runners, Python version 3.9 or higher is required. Please ensure your runner meets this requirement to avoid any issues. We recommend using [setup-python](https://github.com/actions/setup-python) action for installing Python. 🐍

## Inputs

- `cli-version` (action.yml): A specific version of the Cloudsmith CLI to install (optional). 📦
- `api-key` (action.yml): API Key for Cloudsmith (optional). 🔑
- `oidc-namespace` (action.yml): Cloudsmith organisation/namespace for OIDC (optional). 🌐
- `oidc-service-slug` (action.yml): Cloudsmith service account slug for OIDC (optional). 🐌
- `oidc-auth-only` (action.yml): Only perform OIDC authentication without installing the CLI (optional, default: false). 🔐
- `oidc-auth-retry` (action.yml): Number of retry attempts for OIDC authentication (0-10), 5 seconds delay between retries (optional, default: 3). 🔄
- `pip-install` (action.yml): Install the Cloudsmith CLI via pip (optional). 🐍
- `executable-path` (action.yml): Path to the Cloudsmith CLI executable (optional, default: `GITHUB_WORKSPACE/bin/`). 🛠️

## CLI Configuration Inputs ([documentation](https://github.com/cloudsmith-io/cloudsmith-cli?tab=readme-ov-file#non-credentials-configini))

- `api-host`: API Host for Cloudsmith (optional). 🌐
- `api-proxy`: API Proxy for Cloudsmith (optional). 🔗
- `api-ssl-verify`: Verify SSL certificates for Cloudsmith API (optional). 🔒
- `api-user-agent`: User Agent for Cloudsmith API (optional). 🕵️‍♂️

## Example Usage with OIDC

Cloudsmith OIDC [documentation](https://docs.cloudsmith.com/access-control/openid-connect) 📚

```yaml
uses: cloudsmith-io/cloudsmith-cli-action@v1.0.3
with:
  oidc-namespace: 'your-oidc-namespace'
  oidc-service-slug: 'your-service-account-slug'
```

## Example Usage with API Key

Personal API Key can be found [here](https://cloudsmith.io/user/settings/api/), for CI-CD deployments we recommend using [Service Accounts](https://docs.cloudsmith.com/accounts-and-teams/service-accounts). 🔒

```yaml
uses: cloudsmith-io/cloudsmith-cli-action@v1.0.3
with:
  api-key: 'your-api-key'
```

## Example Usage with OIDC Authentication Only

If you only need to authenticate with Cloudsmith's API without installing the CLI:

```yaml
uses: cloudsmith-io/cloudsmith-cli-action@v1.0.3
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

Full CLI feature list can be found [here](https://github.com/cloudsmith-io/cloudsmith-cli?tab=readme-ov-file#features) 📖


### Publish a package

For all supported package formats and upload commands please visit our [Supported Formats](https://docs.cloudsmith.com/formats) page. 📦

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
        uses: cloudsmith-io/cloudsmith-cli-action@v1.0.3
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

If you have any questions or need further assistance, please open an issue on GitHub. We're here to help! 💬 Alternatively, you can contact us at [support.cloudsmith.com](https://support.cloudsmith.com/).

