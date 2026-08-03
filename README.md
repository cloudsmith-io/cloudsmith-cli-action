# Cloudsmith CLI Setup Action

[![Test status](https://github.com/cloudsmith-io/cloudsmith-cli-action/actions/workflows/test.yml/badge.svg)](https://github.com/cloudsmith-io/cloudsmith-cli-action/actions/workflows/test.yml)
[![GitHub Marketplace](https://img.shields.io/badge/Marketplace-Cloudsmith%20CLI%20Install-0366d6?logo=github)](https://github.com/marketplace/actions/cloudsmith-cli-install-action)
[![Latest release](https://img.shields.io/github/v/release/cloudsmith-io/cloudsmith-cli-action)](https://github.com/cloudsmith-io/cloudsmith-cli-action/releases)
[![License](https://img.shields.io/github/license/cloudsmith-io/cloudsmith-cli-action)](LICENSE)

Install the standalone [Cloudsmith CLI](https://github.com/cloudsmith-io/cloudsmith-cli), add it to `PATH`, and configure authentication for the rest of a GitHub Actions job. The action does not require Python or Node.js on the runner.

[Quick start](#quick-start) · [Configuration](#configuration) · [Outputs](#outputs) · [Migration guide](#migrating-from-v2) · [Contributing](#contributing)

## At a glance

| Capability | Support |
| --- | --- |
| Authentication | OpenID Connect (OIDC) or API key |
| Runners | Linux, macOS, and Windows |
| Architectures | x86-64, plus Linux and macOS ARM64 |
| Runtime dependencies | No Python or Node.js; `export-auth-token` additionally uses `jq` on Linux and macOS |
| Version selection | Latest release or a specific CLI version |

## Quick start

### Authenticate with OIDC

OIDC is the recommended option for CI/CD because it uses short-lived credentials instead of a stored API key. Before using this example, configure a Cloudsmith service account and an OIDC provider by following the [Cloudsmith OIDC documentation](https://docs.cloudsmith.com/authentication/openid-connect).

> [!IMPORTANT]
> The workflow or job must grant `id-token: write`. Without this permission, GitHub cannot issue the OIDC token used to authenticate with Cloudsmith.

```yaml
permissions:
  id-token: write
  contents: read

steps:
  - uses: cloudsmith-io/cloudsmith-cli-action@v3
    with:
      oidc-namespace: "YOUR-NAMESPACE"
      oidc-service-slug: "YOUR-SERVICE-ACCOUNT"

  - run: cloudsmith whoami
```

### Authenticate with an API key

Store the API key as a GitHub Actions secret and pass it to the action. For automated workflows, use a [Cloudsmith service account](https://docs.cloudsmith.com/accounts-and-teams/service-accounts) rather than a personal API key.

```yaml
steps:
  - uses: cloudsmith-io/cloudsmith-cli-action@v3
    with:
      api-key: ${{ secrets.CLOUDSMITH_API_KEY }}

  - run: cloudsmith whoami
```

Personal API keys are available from [Cloudsmith API settings](https://cloudsmith.io/user/settings/api/).

## Authentication

Choose one of the following authentication methods:

| Method | Inputs | Credential handling | Best suited to |
| --- | --- | --- | --- |
| OIDC | `oidc-namespace` and `oidc-service-slug` | The CLI exchanges a GitHub OIDC token on its first authenticated command | CI/CD workflows |
| API key | `api-key` | The action masks and exports the key for later steps | Workflows that cannot use OIDC |

With OIDC, the action exports the service account context needed by the CLI. The Cloudsmith access token is requested only when the CLI first needs to authenticate and is not exposed by default. If a later step needs the effective credential itself — for example to configure npm, pip, or `docker login` against a Cloudsmith registry — set `export-auth-token: "true"`. The action runs `cloudsmith credential-helper generic` once, validates its versioned response, masks and exports its `password` as `CLOUDSMITH_API_KEY`, exports its package-manager username (`token`) as `CLOUDSMITH_USERNAME`, and sets the compatibility `oidc-token` output. This requires Cloudsmith CLI 1.21.0 or later. On a self-hosted Linux or macOS runner, `jq` must also be available on `PATH`.

```yaml
- uses: cloudsmith-io/cloudsmith-cli-action@v3
  with:
    oidc-namespace: "YOUR-NAMESPACE"
    oidc-service-slug: "YOUR-SERVICE-ACCOUNT"
    export-auth-token: "true"

- name: Authenticate npm against Cloudsmith
  run: npm config set //npm.cloudsmith.io/YOUR-NAMESPACE/YOUR-REPOSITORY/:_authToken "$CLOUDSMITH_API_KEY"
```

```mermaid
flowchart LR
    A[Setup action] -->|Installs CLI and exports OIDC settings| B[Cloudsmith CLI command]
    B -->|Requests identity token| C[GitHub OIDC]
    C -->|Exchanges identity| D[Cloudsmith]
```

Set `verify-auth: "true"` to run `cloudsmith whoami` during setup and fail early if authentication is not configured correctly.

## Configuration

An authentication method is required: provide `api-key`, or provide both `oidc-namespace` and `oidc-service-slug`.

### Installation inputs

| Input | Description | Required | Default |
| --- | --- | --- | --- |
| `cli-version` | CLI version to install, such as `1.20.0` | No | `latest` |
| `install-directory` | Root directory for versioned CLI installations | No | `RUNNER_TEMP/cloudsmith-cli` |
| `verify-auth` | Run `cloudsmith whoami` after setup | No | `false` |

### Authentication inputs

| Input | Description | Required | Default |
| --- | --- | --- | --- |
| `api-key` | Cloudsmith API key | For API-key authentication | — |
| `oidc-namespace` | Cloudsmith organisation or namespace | For OIDC authentication | — |
| `oidc-service-slug` | Cloudsmith service account slug | For OIDC authentication | — |
| `oidc-audience` | Audience requested for the GitHub OIDC token | No | `https://github.com/{repository-owner}` |
| `export-auth-token` | Resolve the effective credential through `cloudsmith credential-helper generic`, export its password as `CLOUDSMITH_API_KEY`, and export its username as `CLOUDSMITH_USERNAME` (requires CLI 1.21.0+) | No | `false` |
| `oidc-auth-only` | Deprecated alias for `export-auth-token`; when `true`, it enables the same credential-helper flow | No | `false` |

### API configuration inputs

| Input | Description | Required | Default |
| --- | --- | --- | --- |
| `api-host` | Cloudsmith API host override | No | — |
| `api-proxy` | Proxy used to reach the Cloudsmith API | No | — |
| `api-ssl-verify` | Whether to verify API SSL certificates: `true` or `false` | No | CLI default |
| `api-user-agent` | User agent override for Cloudsmith API requests | No | — |

## Outputs

| Output | Description |
| --- | --- |
| `cli-version` | Resolved Cloudsmith CLI version |
| `target` | Resolved binary target, such as `linux-x86_64-gnu` |
| `cli-path` | Absolute path to the Cloudsmith CLI executable |
| `bin-directory` | Directory added to `PATH` for later steps |
| `oidc-token` | Effective authentication token resolved when `export-auth-token` or its `oidc-auth-only` alias is enabled (masked in logs; retained for compatibility) |

Access an output through the action step's `id`:

```yaml
steps:
  - name: Set up Cloudsmith CLI
    id: cloudsmith
    uses: cloudsmith-io/cloudsmith-cli-action@v3
    with:
      api-key: ${{ secrets.CLOUDSMITH_API_KEY }}

  - run: echo "Installed Cloudsmith CLI ${{ steps.cloudsmith.outputs.cli-version }}"
```

## Environment variables

The action configures later steps by exporting the environment variables that correspond to the supplied inputs.

| Input | Environment variable |
| --- | --- |
| `api-key` | `CLOUDSMITH_API_KEY` |
| `oidc-namespace` | `CLOUDSMITH_ORG` |
| `oidc-service-slug` | `CLOUDSMITH_SERVICE_SLUG` |
| `oidc-audience` | `CLOUDSMITH_OIDC_AUDIENCE` |
| `api-host` | `CLOUDSMITH_API_HOST` |
| `api-proxy` | `CLOUDSMITH_API_PROXY` |
| `api-user-agent` | `CLOUDSMITH_API_USER_AGENT` |
| `api-ssl-verify` | `CLOUDSMITH_WITHOUT_API_SSL_VERIFY` |
| `export-auth-token` | `CLOUDSMITH_API_KEY` (effective credential) and `CLOUDSMITH_USERNAME` (`token`) |

## Publish a package

The following workflow installs the CLI with OIDC authentication and publishes a Python package:

```yaml
name: Publish Python package

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
      - uses: actions/checkout@v4

      - name: Set up Cloudsmith CLI
        uses: cloudsmith-io/cloudsmith-cli-action@v3
        with:
          oidc-namespace: "YOUR-NAMESPACE"
          oidc-service-slug: "YOUR-SERVICE-ACCOUNT"

      - name: Publish package
        run: cloudsmith push python YOUR-NAMESPACE/YOUR-REPOSITORY dist/*.tar.gz
```

See [Supported Formats](https://docs.cloudsmith.com/formats) for the upload command and options for each package format.

## Migrating from v2

Version 3 installs the standalone CLI instead of the Python package. Existing workflows that use `api-key`, or the `oidc-namespace` and `oidc-service-slug` pair, can keep those authentication inputs and the existing default OIDC audience.

> [!NOTE]
> OIDC authentication is now lazy: the CLI exchanges the token on its first authenticated command. Use `verify-auth: "true"` if the setup step should validate credentials immediately.

<details>
<summary><strong>View removed inputs, outputs, and migration steps</strong></summary>

### Removed and deprecated v2 inputs

| v2 input | Migration |
| --- | --- |
| `pip-install` | Remove it. Version 3 always installs the standalone binary. |
| `oidc-auth-only` | Deprecated alias for `export-auth-token`; when `true`, it enables the same `cloudsmith credential-helper generic` flow. |
| `oidc-auth-retry` | Remove it. The CLI manages the token exchange and retries. |
| `oidc-token-validate` | Replace it with `verify-auth: "true"`. |
| `executable-path` | Use `install-directory` to control the installation root. Use the `cli-path` or `bin-directory` output for the resolved location. |

### `oidc-token` output

By default the action no longer receives or exposes the Cloudsmith access token; authenticate subsequent requests with the CLI. Set `export-auth-token: "true"` to resolve the effective credential through `cloudsmith credential-helper generic`, export it as `CLOUDSMITH_API_KEY`, and restore the `oidc-token` output. `oidc-auth-only: "true"` is a deprecated alias that enables the same behavior. Requires Cloudsmith CLI 1.21.0 or later.

### API configuration

The action no longer writes a configuration file. Values supplied through `api-host`, `api-proxy`, `api-ssl-verify`, and `api-user-agent` are exported as `CLOUDSMITH_*` environment variables for later steps.

</details>

## Contributing

See the [contribution guide](CONTRIBUTION.md) for the repository layout, local validation commands, and pull request process.

## Support

For help, [open a GitHub issue](https://github.com/cloudsmith-io/cloudsmith-cli-action/issues) or contact [Cloudsmith Support](https://support.cloudsmith.com/).

## License

This project is available under the [MIT License](LICENSE).
