# Contributing

Thank you for considering contributing to the Cloudsmith CLI Setup action!

## Repository Layout

- `action.yml` — composite action definition.
- `scripts/setup.sh` / `scripts/setup.ps1` — wrapper scripts run by the action.
- `installer/install.sh` / `installer/install.ps1` — vendored copies of the
  Cloudsmith CLI installer. Do not edit these by hand; they are updated by
  re-vendoring a new installer release together with `installer/VERSION` and
  `installer/SHA256SUMS`. CI fails if the checksums do not match.

## Creating a Pull Request

1. Fork the repository and clone your fork.
2. Create a branch: `git checkout -b <branch-name>`.
3. Make your changes and validate them locally:

   ```sh
   bash -n scripts/setup.sh
   shellcheck --severity=style scripts/setup.sh
   pwsh -Command "Invoke-ScriptAnalyzer -Path scripts/setup.ps1 -Settings PSGallery -EnableExit"
   ```

4. Commit, push to your fork, and open a pull request.

## Variables and Secrets for GitHub Actions

The install and validation test jobs run without any configuration. To run the
authentication test jobs in your fork, configure the following under
"Settings" > "Secrets and variables" > "Actions":

Variables:

- `CLOUDSMITH_NAMESPACE`: your Cloudsmith OIDC namespace.
- `CLOUDSMITH_SERVICE_SLUG`: your Cloudsmith OIDC service account slug.

Secrets:

- `CLOUDSMITH_API_KEY`: your Cloudsmith API key.

Jobs that need missing variables or secrets are skipped automatically.

Thank you for contributing! If you have any questions, feel free to open an
issue or reach out to the maintainers.
