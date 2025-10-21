Thank you for considering contributing to the Cloudsmith CLI Install Action! Here are the steps to create a Pull Request (PR) and the necessary variables and secrets for GitHub Actions.
\
> Note: This repository uses a Husky pre-commit hook to automatically build and stage the bundled action code in `dist/index.js`. You should not manually edit files under `dist/`.
## How to Create PRs (Fork)
### Fork the Repository:
- Navigate to the Cloudsmith CLI Install Action repository.
- Click the "Fork" button at the top right of the page.

### Clone Your Fork:
- Open your terminal and clone your forked repository:

```
git clone <your-forked-repo-url>
```

### Create a New Branch:
- Create a new branch for your feature or bug fix:

```
git checkout -b <branch-name>
```

### Make Your Changes:
- Make the necessary changes in your local repository.

### Commit Your Changes:
- Commit your changes with a descriptive message:

```
git commit -m "Your commit message"
```

The pre-commit hook will:

- Ensure dependencies are installed (if `node_modules` is missing)
- Run `npm run build` (which bundles the action via `@vercel/ncc` into `dist/index.js`)
- Stage `dist/index.js` if it changed

If the build fails, the commit is aborted. Fix issues (lint, syntax, missing deps) and commit again.

To skip the hook (rarely needed, e.g. emergency hotfix where build already validated), you can use:

```
git commit -m "Your commit message" --no-verify
```

Please avoid skipping unless absolutely necessary—having `dist/` in-sync with source ensures tagged releases run reliably.

### Push Your Changes:
- Push your changes to your forked repository:

```
git push origin <branch-name>
```

### Create a Pull Request:
- Navigate to your forked repository on GitHub.
- Click the "Compare & pull request" button.
- Provide a descriptive title and detailed description of your changes.
- Click "Create pull request".

## Running Locally
To run this project locally, you need to have Node.js and npm installed. Follow these steps:

- Install the dependencies:

```
npm install
```

- Build the project:

```
npm run build
```

You normally do not need to run `npm run build` manually before committing; the pre-commit hook will handle it. Running it locally first can still help surface errors earlier.

- Commit your changes to GitHub.
- Configure the variables below and trigger the test action.

## Variables and Secrets for GitHub Actions
To run the GitHub Actions workflows, you need to set up the following variables and secrets in your repository:

### Variables:
- NAMESPACE: Your Cloudsmith OIDC namespace.
- SERVICE_ACCOUNT: Your Cloudsmith OIDC service account slug.

### Secrets:
- CLOUDSMITH_API_KEY: Your Cloudsmith API key.

To add these variables and secrets:

1. Navigate to Your Repository Settings:
    - Go to your repository on GitHub.
    - Click on "Settings".

2. Add Variables:
    - Go to "Secrets and variables" > "Actions" > "Variables".
    - Click "New repository variable" and add NAMESPACE and SERVICE_ACCOUNT.

3. Add Secrets:
    - Go to "Secrets and variables" > "Actions" > "Secrets".
    - Click "New repository secret" and add CLOUDSMITH_API_KEY.

## Example Commands/Code to Change
Here is an example of how you might modify the [`test_install.yml`](".github/workflows/test_install.yml") workflow to use a different CLI version and authentication method:

```yaml
- name: Install Cloudsmith CLI
  uses: cloudsmith-io/cloudsmith-cli-action@v1
  with:
     cli-version: 1.3.0
     auth-method: token
     token: ${{ secrets.CLOUDSMITH_API_KEY }}
```

You can modify other inputs similarly based on your requirements.

Thank you for contributing! If you have any questions, feel free to open an issue or reach out to the maintainers.
