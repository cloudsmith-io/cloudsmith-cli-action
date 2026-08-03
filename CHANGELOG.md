# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
---

## [3.1.0] - 2026-08-03
---
### Added

- `export-auth-token` now resolves the effective credential through `cloudsmith credential-helper generic`, validates its version-1 JSON response, exports `password` as `CLOUDSMITH_API_KEY`, exports the helper's `username` as `CLOUDSMITH_USERNAME`, and preserves the masked `oidc-token` compatibility output. `oidc-auth-only` remains a deprecated alias that enables the same flow.

## [3.0.0] - 2026-07-30
---
### Breaking Changes

- **Composite action** - The action is now a composite action that installs the standalone Cloudsmith CLI binary via bundled installer scripts. No Python or Node.js runtime is required.
- **CLI-native OIDC** - The CLI performs the OIDC token exchange on its first authenticated command; the action only exports `CLOUDSMITH_ORG`, `CLOUDSMITH_SERVICE_SLUG`, and `CLOUDSMITH_OIDC_AUDIENCE`. The default audience remains `https://github.com/{repository-owner}`.
- **Removed inputs** - `pip-install`, `oidc-auth-only`, `oidc-auth-retry`, `oidc-token-validate`, and `executable-path`. See the README migration table.
- **Removed output** - `oidc-token`. The action never holds a Cloudsmith token.
- **No config file** - `api-host`, `api-proxy`, `api-ssl-verify`, and `api-user-agent` are exported as `CLOUDSMITH_*` environment variables instead of being written to a config file.

### Added

- `install-directory` input to control where versioned CLI installations live.
- `verify-auth` input to run `cloudsmith whoami` after setup.
- `cli-version`, `target`, `cli-path`, and `bin-directory` outputs.
- Linux ARM64 (glibc and musl) and macOS ARM64 support via the standalone binaries.

## [2.0.3] - 2026-05-08
---
### Security

- Mask the OIDC-issued Cloudsmith API token as a secret so it is replaced with `***` in any subsequent workflow log line. The token was previously exported via `core.exportVariable("CLOUDSMITH_API_KEY", token)` and `core.setOutput('oidc-token', token)` without first calling `core.setSecret(token)`, so a downstream step that printed `$CLOUDSMITH_API_KEY` (e.g. via `set -x` or accidental `echo`) would leak the bearer token in clear text.

### Fixed

- `pip-install: 'true'`: the Cloudsmith Python index URL is now actually forwarded to `pip install`. Previously, `--index-url=...` was passed as the third positional argument to `@actions/exec`'s `exec()` (which is the **options** object, not extra CLI args), so the flag was silently dropped and `cloudsmith-cli` was resolved from PyPI alone. The flag is now passed inside the args array as `--extra-index-url=...`, so pip searches both PyPI and the Cloudsmith index when resolving `cloudsmith-cli` and its transitive dependencies (`click`, `click-configfile`, etc.).

## [2.0.1] - 2025-12-23
---
### Changed

- Replaced `axios` with native Node Fetch

## [2.0.0] - 2025-12-19
---
### Breaking Changes

- **Node.js requirement updated to 24+** - The action now requires Node.js 24 or higher. If you're using this action, GitHub Actions will automatically use Node 24 runtime. For development and testing, ensure you have Node 24+ installed.
- **OIDC audience default changed** - The `oidc-audience` input now defaults to `https://github.com/{org-name}` (using `GITHUB_REPOSITORY_OWNER`) instead of the generic `api://AzureADTokenExchange`. This provides organization-specific audience claims for better security. If you are currently relying on the old default and using the `aud` claim for validation, you must either update your validation logic or explicitly set `oidc-audience: 'api://AzureADTokenExchange'` to maintain the previous behavior.

### Changed

- Updated `action.yml` to use `node24` runtime
- Updated test workflows to run on Node 24
- Updated documentation to v2
- OIDC Audience defaults to `https://github.com/{org-name}` from `api://AzureADTokenExchange`
- Replaced `axios` with native `fetch` API to fix Node.js 24 `url.parse()` deprecation warning (DEP0169) and reduce bundle size

## [1.0.0] - 2024
---
### Initial Release

- Install Cloudsmith CLI via pip or executable download
- OIDC authentication support
- API Key authentication support
- OIDC-only authentication mode
- Configurable retry logic for OIDC authentication
- CLI configuration options (api-host, api-proxy, api-ssl-verify, api-user-agent)
- Support for Linux, macOS, and Windows runners
- Node 20 runtime support

[1.0.0]: https://github.com/cloudsmith-io/cloudsmith-cli-action/releases/tag/v1.0.0
