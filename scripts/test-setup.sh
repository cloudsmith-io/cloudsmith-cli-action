#!/usr/bin/env bash
set -euo pipefail

setup_script="$(cd "$(dirname "$0")" && pwd)/setup.sh"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/installer" "$test_root/bin"

cat > "$test_root/installer/install.sh" <<'EOF'
#!/bin/sh
while [ "$1" != "--output-file" ]; do shift; done
printf 'version=1.21.0\ntarget=test\nbin_dir=%s/bin\nexecutable=%s/bin/cloudsmith\n' \
  "$GITHUB_ACTION_PATH" "$GITHUB_ACTION_PATH" > "$2"
EOF

cat > "$test_root/bin/cloudsmith" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  "credential-helper generic")
    echo helper >> "$GITHUB_ACTION_PATH/helper.log"
    # Match CLI precedence: an API key wins over OIDC.
    token="${CLOUDSMITH_API_KEY:-}"
    if [[ -z "$token" ]]; then
      echo "$CLOUDSMITH_SERVICE_SLUG" >> "$GITHUB_ACTION_PATH/exchanges.log"
      token="token-$CLOUDSMITH_SERVICE_SLUG"
    fi
    printf '{"version":1,"username":"token","password":"%s"}\n' "$token"
    ;;
  whoami) echo "${CLOUDSMITH_API_KEY:-}" >> "$GITHUB_ACTION_PATH/verified.log" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$test_root/bin/cloudsmith"

export GITHUB_ACTION_PATH="$test_root" RUNNER_TEMP="$test_root"
export GITHUB_ENV="$test_root/env" GITHUB_OUTPUT="$test_root/output" GITHUB_PATH="$test_root/path"
export GITHUB_REPOSITORY_OWNER=test-owner ACTIONS_ID_TOKEN_REQUEST_URL=https://example.invalid/oidc
export INPUT_CLI_VERSION=latest INPUT_INSTALL_DIRECTORY="" INPUT_API_KEY=""
export INPUT_OIDC_NAMESPACE=test-org INPUT_OIDC_SERVICE_SLUG=pull-only INPUT_OIDC_AUDIENCE=""
export INPUT_API_HOST="" INPUT_API_PROXY="" INPUT_API_SSL_VERIFY="" INPUT_API_USER_AGENT=""
export INPUT_VERIFY_AUTH=true INPUT_EXPORT_AUTH_TOKEN=true INPUT_OIDC_AUTH_ONLY=false
unset CLOUDSMITH_API_KEY

run_setup() {
  local expected="$1" line
  : > "$GITHUB_ENV"
  : > "$GITHUB_OUTPUT"
  bash "$setup_script"
  # Apply GITHUB_ENV as the runner would before the next action invocation.
  while IFS= read -r line; do
    export "${line?}"
  done < "$GITHUB_ENV"
  test "$CLOUDSMITH_API_KEY" = "$expected"
  test "$(tail -n 1 "$test_root/verified.log")" = "$expected"
  grep -Fx "CLOUDSMITH_API_KEY=$expected" "$GITHUB_ENV"
  if [[ "$INPUT_EXPORT_AUTH_TOKEN" == true || "$INPUT_OIDC_AUTH_ONLY" == true ]]; then
    test "$CLOUDSMITH_USERNAME" = token
    grep -Fx "oidc-token=$expected" "$GITHUB_OUTPUT"
  fi
}

run_setup token-pull-only
export INPUT_OIDC_SERVICE_SLUG=push-capable
run_setup token-push-capable
test "$(cat "$test_root/exchanges.log")" = $'pull-only\npush-capable'
test "$(wc -l < "$test_root/helper.log" | tr -d ' ')" = 2

# Explicit API keys still win, even with OIDC inputs and an inherited token.
export INPUT_API_KEY=explicit-key
run_setup explicit-key
export INPUT_OIDC_NAMESPACE="" INPUT_OIDC_SERVICE_SLUG="" INPUT_API_KEY=api-only-key
run_setup api-only-key
test "$(cat "$test_root/exchanges.log")" = $'pull-only\npush-capable'
test "$(wc -l < "$test_root/helper.log" | tr -d ' ')" = 4

export INPUT_EXPORT_AUTH_TOKEN=false INPUT_API_KEY=unexported-key
run_setup unexported-key
test "$(wc -l < "$test_root/helper.log" | tr -d ' ')" = 4
if grep -q '^oidc-token=' "$GITHUB_OUTPUT"; then
  echo "Unexpected oidc-token output" >&2
  exit 1
fi

# The deprecated alias must also ignore the previously exported API key.
export INPUT_API_KEY="" INPUT_OIDC_NAMESPACE=test-org INPUT_OIDC_SERVICE_SLUG=alias-service
export INPUT_OIDC_AUTH_ONLY=true
run_setup token-alias-service
test "$(cat "$test_root/exchanges.log")" = $'pull-only\npush-capable\nalias-service'
echo "Bash setup tests passed"
