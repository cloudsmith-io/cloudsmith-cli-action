# Cloudsmith CLI Installer

This GitHub Action installs the Cloudsmith CLI and authenticates using OIDC.

## Inputs

- [`org_name`](command:_github.copilot.openSymbolFromReferences?%5B%22org_name%22%2C%5B%7B%22uri%22%3A%7B%22%24mid%22%3A1%2C%22fsPath%22%3A%22%2FUsers%2Fbblizniak%2FGitHub%2Fcloudsmith-cli-action%2F.github%2Fworkflows%2Ftest.yml%22%2C%22external%22%3A%22file%3A%2F%2F%2FUsers%2Fbblizniak%2FGitHub%2Fcloudsmith-cli-action%2F.github%2Fworkflows%2Ftest.yml%22%2C%22path%22%3A%22%2FUsers%2Fbblizniak%2FGitHub%2Fcloudsmith-cli-action%2F.github%2Fworkflows%2Ftest.yml%22%2C%22scheme%22%3A%22file%22%7D%2C%22pos%22%3A%7B%22line%22%3A14%2C%22character%22%3A10%7D%7D%2C%7B%22uri%22%3A%7B%22%24mid%22%3A1%2C%22fsPath%22%3A%22%2FUsers%2Fbblizniak%2FGitHub%2Fcloudsmith-cli-action%2FREADME.md%22%2C%22external%22%3A%22file%3A%2F%2F%2FUsers%2Fbblizniak%2FGitHub%2Fcloudsmith-cli-action%2FREADME.md%22%2C%22path%22%3A%22%2FUsers%2Fbblizniak%2FGitHub%2Fcloudsmith-cli-action%2FREADME.md%22%2C%22scheme%22%3A%22file%22%7D%2C%22pos%22%3A%7B%22line%22%3A14%2C%22character%22%3A2%7D%7D%2C%7B%22uri%22%3A%7B%22%24mid%22%3A1%2C%22fsPath%22%3A%22%2FUsers%2Fbblizniak%2FGitHub%2Fcloudsmith-cli-action%2FREADME.md%22%2C%22external%22%3A%22file%3A%2F%2F%2FUsers%2Fbblizniak%2FGitHub%2Fcloudsmith-cli-action%2FREADME.md%22%2C%22path%22%3A%22%2FUsers%2Fbblizniak%2FGitHub%2Fcloudsmith-cli-action%2FREADME.md%22%2C%22scheme%22%3A%22file%22%7D%2C%22pos%22%3A%7B%22line%22%3A14%2C%22character%22%3A2%7D%7D%5D%5D "Go to definition"): The organization name (required).
- [`service_account_slug`](command:_github.copilot.openSymbolFromReferences?%5B%22service_account_slug%22%2C%5B%7B%22uri%22%3A%7B%22%24mid%22%3A1%2C%22fsPath%22%3A%22%2FUsers%2Fbblizniak%2FGitHub%2Fcloudsmith-cli-action%2F.github%2Fworkflows%2Ftest.yml%22%2C%22external%22%3A%22file%3A%2F%2F%2FUsers%2Fbblizniak%2FGitHub%2Fcloudsmith-cli-action%2F.github%2Fworkflows%2Ftest.yml%22%2C%22path%22%3A%22%2FUsers%2Fbblizniak%2FGitHub%2Fcloudsmith-cli-action%2F.github%2Fworkflows%2Ftest.yml%22%2C%22scheme%22%3A%22file%22%7D%2C%22pos%22%3A%7B%22line%22%3A15%2C%22character%22%3A10%7D%7D%2C%7B%22uri%22%3A%7B%22%24mid%22%3A1%2C%22fsPath%22%3A%22%2FUsers%2Fbblizniak%2FGitHub%2Fcloudsmith-cli-action%2FREADME.md%22%2C%22external%22%3A%22file%3A%2F%2F%2FUsers%2Fbblizniak%2FGitHub%2Fcloudsmith-cli-action%2FREADME.md%22%2C%22path%22%3A%22%2FUsers%2Fbblizniak%2FGitHub%2Fcloudsmith-cli-action%2FREADME.md%22%2C%22scheme%22%3A%22file%22%7D%2C%22pos%22%3A%7B%22line%22%3A15%2C%22character%22%3A2%7D%7D%2C%7B%22uri%22%3A%7B%22%24mid%22%3A1%2C%22fsPath%22%3A%22%2FUsers%2Fbblizniak%2FGitHub%2Fcloudsmith-cli-action%2FREADME.md%22%2C%22external%22%3A%22file%3A%2F%2F%2FUsers%2Fbblizniak%2FGitHub%2Fcloudsmith-cli-action%2FREADME.md%22%2C%22path%22%3A%22%2FUsers%2Fbblizniak%2FGitHub%2Fcloudsmith-cli-action%2FREADME.md%22%2C%22scheme%22%3A%22file%22%7D%2C%22pos%22%3A%7B%22line%22%3A15%2C%22character%22%3A2%7D%7D%5D%5D "Go to definition"): The service account slug (required).
- [`cli-version`](command:_github.copilot.openSymbolFromReferences?%5B%22cli-version%22%2C%5B%7B%22uri%22%3A%7B%22%24mid%22%3A1%2C%22fsPath%22%3A%22%2FUsers%2Fbblizniak%2FGitHub%2Fcloudsmith-cli-action%2Fsrc%2Fdownload-cli.js%22%2C%22external%22%3A%22file%3A%2F%2F%2FUsers%2Fbblizniak%2FGitHub%2Fcloudsmith-cli-action%2Fsrc%2Fdownload-cli.js%22%2C%22path%22%3A%22%2FUsers%2Fbblizniak%2FGitHub%2Fcloudsmith-cli-action%2Fsrc%2Fdownload-cli.js%22%2C%22scheme%22%3A%22file%22%7D%2C%22pos%22%3A%7B%22line%22%3A8%2C%22character%22%3A35%7D%7D%2C%7B%22uri%22%3A%7B%22%24mid%22%3A1%2C%22fsPath%22%3A%22%2FUsers%2Fbblizniak%2FGitHub%2Fcloudsmith-cli-action%2Fsrc%2Fmain.js%22%2C%22external%22%3A%22file%3A%2F%2F%2FUsers%2Fbblizniak%2FGitHub%2Fcloudsmith-cli-action%2Fsrc%2Fmain.js%22%2C%22path%22%3A%22%2FUsers%2Fbblizniak%2FGitHub%2Fcloudsmith-cli-action%2Fsrc%2Fmain.js%22%2C%22scheme%22%3A%22file%22%7D%2C%22pos%22%3A%7B%22line%22%3A2%2C%22character%22%3A43%7D%7D%5D%5D "Go to definition"): A specific version of the Cloudsmith CLI to install (optional).
- [`api-key`](command:_github.copilot.openSymbolFromReferences?%5B%22api-key%22%2C%5B%7B%22uri%22%3A%7B%22%24mid%22%3A1%2C%22fsPath%22%3A%22%2FUsers%2Fbblizniak%2FGitHub%2Fcloudsmith-cli-action%2Fsrc%2Fmain.js%22%2C%22external%22%3A%22file%3A%2F%2F%2FUsers%2Fbblizniak%2FGitHub%2Fcloudsmith-cli-action%2Fsrc%2Fmain.js%22%2C%22path%22%3A%22%2FUsers%2Fbblizniak%2FGitHub%2Fcloudsmith-cli-action%2Fsrc%2Fmain.js%22%2C%22scheme%22%3A%22file%22%7D%2C%22pos%22%3A%7B%22line%22%3A9%2C%22character%22%3A34%7D%7D%5D%5D "Go to definition"): API Key for Cloudsmith (optional).
- [`oidc-namespace`](command:_github.copilot.openSymbolFromReferences?%5B%22oidc-namespace%22%2C%5B%7B%22uri%22%3A%7B%22%24mid%22%3A1%2C%22fsPath%22%3A%22%2FUsers%2Fbblizniak%2FGitHub%2Fcloudsmith-cli-action%2Fsrc%2Fmain.js%22%2C%22external%22%3A%22file%3A%2F%2F%2FUsers%2Fbblizniak%2FGitHub%2Fcloudsmith-cli-action%2Fsrc%2Fmain.js%22%2C%22path%22%3A%22%2FUsers%2Fbblizniak%2FGitHub%2Fcloudsmith-cli-action%2Fsrc%2Fmain.js%22%2C%22scheme%22%3A%22file%22%7D%2C%22pos%22%3A%7B%22line%22%3A1%2C%22character%22%3A28%7D%7D%5D%5D "Go to definition"): Cloudsmith organisation/namespace for OIDC (optional).
- [`pip-install`](command:_github.copilot.openSymbolFromReferences?%5B%22pip-install%22%2C%5B%7B%22uri%22%3A%7B%22%24mid%22%3A1%2C%22fsPath%22%3A%22%2FUsers%2Fbblizniak%2FGitHub%2Fcloudsmith-cli-action%2Fsrc%2Fdownload-cli.js%22%2C%22external%22%3A%22file%3A%2F%2F%2FUsers%2Fbblizniak%2FGitHub%2Fcloudsmith-cli-action%2Fsrc%2Fdownload-cli.js%22%2C%22path%22%3A%22%2FUsers%2Fbblizniak%2FGitHub%2Fcloudsmith-cli-action%2Fsrc%2Fdownload-cli.js%22%2C%22scheme%22%3A%22file%22%7D%2C%22pos%22%3A%7B%22line%22%3A10%2C%22character%22%3A35%7D%7D%5D%5D "Go to definition"): Install the Cloudsmith CLI via pip (optional).
- [`executable-path`](command:_github.copilot.openSymbolFromReferences?%5B%22executable-path%22%2C%5B%7B%22uri%22%3A%7B%22%24mid%22%3A1%2C%22fsPath%22%3A%22%2FUsers%2Fbblizniak%2FGitHub%2Fcloudsmith-cli-action%2Fsrc%2Fdownload-cli.js%22%2C%22external%22%3A%22file%3A%2F%2F%2FUsers%2Fbblizniak%2FGitHub%2Fcloudsmith-cli-action%2Fsrc%2Fdownload-cli.js%22%2C%22path%22%3A%22%2FUsers%2Fbblizniak%2FGitHub%2Fcloudsmith-cli-action%2Fsrc%2Fdownload-cli.js%22%2C%22scheme%22%3A%22file%22%7D%2C%22pos%22%3A%7B%22line%22%3A9%2C%22character%22%3A39%7D%7D%5D%5D "Go to definition"): Path to the Cloudsmith CLI executable (optional, default: `GITHUB_WORKSPACE/bin/`).

## Outputs

- [`oidc-token`](command:_github.copilot.openSymbolFromReferences?%5B%22oidc-token%22%2C%5B%7B%22uri%22%3A%7B%22%24mid%22%3A1%2C%22fsPath%22%3A%22%2FUsers%2Fbblizniak%2FGitHub%2Fcloudsmith-cli-action%2Fsrc%2Fmain.js%22%2C%22external%22%3A%22file%3A%2F%2F%2FUsers%2Fbblizniak%2FGitHub%2Fcloudsmith-cli-action%2Fsrc%2Fmain.js%22%2C%22path%22%3A%22%2FUsers%2Fbblizniak%2FGitHub%2Fcloudsmith-cli-action%2Fsrc%2Fmain.js%22%2C%22scheme%22%3A%22file%22%7D%2C%22pos%22%3A%7B%22line%22%3A1%2C%22character%22%3A28%7D%7D%5D%5D "Go to definition"): JWT token generated by the Cloudsmith CLI setup action.

## Example Usage

```yaml
uses: your-username/cloudsmith-github-action@v1
with:
  org_name: 'your-org-name'
  service_account_slug: 'your-service-account-slug'
  cli-version: 'latest'
  api-key: 'your-api-key'
  oidc-namespace: 'your-oidc-namespace'
  pip-install: 'true'
  executable-path: 'your/executable/path'
```

## Example GitHub Actions Workflow

Here is an example of a GitHub Actions workflow that uses this action to install and authenticate the Cloudsmith CLI, and then verifies the installation and authentication:

```yaml
name: "Test Cloudsmith CLI Installer"
on:
  push:
  pull_request:
  workflow_dispatch:
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: "Run Cloudsmith CLI Installer"
        uses: your-username/cloudsmith-github-action@v1
        with:
          org_name: "your-org-name"
          service_account_slug: "your-service-account-slug"
      - name: "Verify Cloudsmith CLI Installation"
        run: |
          cloudsmith --version
      - name: "Verify Cloudsmith CLI Authentication"
        run: |
          cloudsmith whoami
```

## License

This project is licensed under the MIT License - see the [`LICENSE`]("LICENSE") file for details.