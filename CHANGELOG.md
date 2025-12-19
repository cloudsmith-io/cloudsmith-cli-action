# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
---

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
