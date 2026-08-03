#!/usr/bin/env bash
# Runs the vendored installer and configures Cloudsmith CLI authentication
# for later workflow steps.
set -euo pipefail

fail() {
  echo "::error::$*" >&2
  exit 1
}

# Values are written line-by-line, so a newline would inject extra variables.
append_env() {
  local name="$1"
  local value="$2"
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] \
    || fail "$name must not contain a newline"
  printf '%s=%s\n' "$name" "$value" >> "$GITHUB_ENV"
  export "$name=$value"
}

read_result() {
  awk -v wanted="$1" '
    index($0, wanted "=") == 1 {
      sub(/^[^=]*=/, "")
      print
      exit
    }
  ' "$result_file"
}

has_oidc_namespace="no"
has_oidc_service="no"
[[ -z "$INPUT_OIDC_NAMESPACE" ]] || has_oidc_namespace="yes"
[[ -z "$INPUT_OIDC_SERVICE_SLUG" ]] || has_oidc_service="yes"

if [[ "$has_oidc_namespace" != "$has_oidc_service" ]]; then
  fail "oidc-namespace and oidc-service-slug must be supplied together"
fi

if [[ -z "$INPUT_API_KEY" && "$has_oidc_namespace" == "no" ]]; then
  fail "No authentication inputs were provided. Set 'api-key', or set 'oidc-namespace' and 'oidc-service-slug' (OIDC also requires the 'id-token: write' permission on the workflow or job)."
fi

if [[ -n "$INPUT_OIDC_AUDIENCE" && "$has_oidc_namespace" == "no" ]]; then
  fail "oidc-audience requires oidc-namespace and oidc-service-slug"
fi

if [[ "$has_oidc_namespace" == "yes" && -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ]]; then
  fail "OIDC authentication requires an ID token. Add 'permissions: id-token: write' to your workflow or job."
fi

api_ssl_verify="$(printf '%s' "$INPUT_API_SSL_VERIFY" | tr '[:upper:]' '[:lower:]')"
case "$api_ssl_verify" in
  ""|true|false) ;;
  *) fail "api-ssl-verify must be true, false, or empty" ;;
esac

verify_auth="$(printf '%s' "$INPUT_VERIFY_AUTH" | tr '[:upper:]' '[:lower:]')"
case "$verify_auth" in
  true|false) ;;
  *) fail "verify-auth must be true or false" ;;
esac

export_auth_token="$(printf '%s' "$INPUT_EXPORT_AUTH_TOKEN" | tr '[:upper:]' '[:lower:]')"
case "$export_auth_token" in
  true|false) ;;
  *) fail "export-auth-token must be true or false" ;;
esac

oidc_auth_only="$(printf '%s' "$INPUT_OIDC_AUTH_ONLY" | tr '[:upper:]' '[:lower:]')"
case "$oidc_auth_only" in
  true|false) ;;
  *) fail "oidc-auth-only must be true or false" ;;
esac
if [[ "$oidc_auth_only" == "true" ]]; then
  echo "::warning::The 'oidc-auth-only' input is deprecated; use 'export-auth-token'. Both resolve credentials through 'cloudsmith credential-helper generic'."
  export_auth_token="true"
fi

cli_version="$INPUT_CLI_VERSION"
if [[ -z "$cli_version" ]]; then
  cli_version="latest"
fi

install_root="$INPUT_INSTALL_DIRECTORY"
[[ "$install_root" != *$'\n'* && "$install_root" != *$'\r'* ]] \
  || fail "install-directory must not contain a newline"
if [[ -z "$install_root" ]]; then
  install_root="${RUNNER_TEMP}/cloudsmith-cli"
fi

result_file="$(mktemp "${RUNNER_TEMP}/cloudsmith-installer-result.XXXXXX")"
trap 'rm -f "$result_file"' EXIT

sh "$GITHUB_ACTION_PATH/installer/install.sh" \
  --version "$cli_version" \
  --install-root "$install_root" \
  --output-file "$result_file"

resolved_version="$(read_result version)"
target="$(read_result target)"
bin_dir="$(read_result bin_dir)"
executable="$(read_result executable)"

[[ -n "$resolved_version" && -n "$target" && -n "$bin_dir" && -n "$executable" ]] \
  || fail "Installer did not return the expected result fields"
# These values are written line-by-line to the GitHub command files.
for value in "$resolved_version" "$target" "$bin_dir" "$executable"; do
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] \
    || fail "Installer result must not contain a newline"
done
[[ -x "$executable" ]] || fail "Cloudsmith executable was not installed at $executable"

printf '%s\n' "$bin_dir" >> "$GITHUB_PATH"
export PATH="$bin_dir:$PATH"

if [[ -n "$INPUT_API_KEY" ]]; then
  [[ "$INPUT_API_KEY" != *$'\n'* && "$INPUT_API_KEY" != *$'\r'* ]] \
    || fail "api-key must not contain a newline"
  echo "::add-mask::$INPUT_API_KEY"
  append_env CLOUDSMITH_API_KEY "$INPUT_API_KEY"
fi

if [[ "$has_oidc_namespace" == "yes" ]]; then
  audience="$INPUT_OIDC_AUDIENCE"
  if [[ -z "$audience" ]]; then
    # Keep the v2 default audience so existing Cloudsmith OIDC claim
    # mappings keep working after upgrading to v3.
    audience="https://github.com/${GITHUB_REPOSITORY_OWNER}"
  fi

  append_env CLOUDSMITH_ORG "$INPUT_OIDC_NAMESPACE"
  append_env CLOUDSMITH_SERVICE_SLUG "$INPUT_OIDC_SERVICE_SLUG"
  append_env CLOUDSMITH_OIDC_AUDIENCE "$audience"
fi

api_host="$INPUT_API_HOST"
if [[ -n "$api_host" && "$api_host" != *"://"* ]]; then
  # Match v2, which prefixed bare hosts with https://.
  api_host="https://$api_host"
fi
[[ -z "$api_host" ]] || append_env CLOUDSMITH_API_HOST "$api_host"
[[ -z "$INPUT_API_PROXY" ]] || append_env CLOUDSMITH_API_PROXY "$INPUT_API_PROXY"
[[ -z "$INPUT_API_USER_AGENT" ]] || append_env CLOUDSMITH_API_USER_AGENT "$INPUT_API_USER_AGENT"

case "$api_ssl_verify" in
  true) append_env CLOUDSMITH_WITHOUT_API_SSL_VERIFY "false" ;;
  false) append_env CLOUDSMITH_WITHOUT_API_SSL_VERIFY "true" ;;
esac

exported_token=""
credential_username=""
if [[ "$export_auth_token" == "true" ]]; then
  command -v jq >/dev/null 2>&1 \
    || fail "The 'export-auth-token' input requires jq on Linux and macOS runners."

  # Resolve once: the helper performs the OIDC exchange when OIDC is the
  # effective source and emits a versioned JSON credential document.
  if ! credential_document="$("$executable" credential-helper generic)"; then
    fail "Failed to resolve credentials. 'export-auth-token' requires Cloudsmith CLI 1.21.0 or later and valid credentials."
  fi

  # Validate the protocol before extracting the password. Never assign the
  # raw JSON document to CLOUDSMITH_API_KEY.
  if ! credential_values="$(
    printf '%s' "$credential_document" | jq -er '
      if type == "object"
        and (keys == ["password", "username", "version"])
        and (.version == 1)
        and (.username == "token")
        and (.password | type == "string" and length > 0)
        and (.password | test("[\\r\\n]") | not)
      then .username, .password
      else error("unsupported credential-helper response")
      end
    '
  )"; then
    fail "The CLI returned an invalid or unsupported credential-helper response."
  fi
  [[ "$credential_values" == *$'\n'* ]] \
    || fail "The CLI returned an incomplete credential-helper response."
  credential_username="${credential_values%%$'\n'*}"
  exported_token="${credential_values#*$'\n'}"

  [[ -n "$exported_token" ]] \
    || fail "The CLI returned an empty token"
  [[ "$exported_token" != *$'\n'* && "$exported_token" != *$'\r'* ]] \
    || fail "The CLI returned a token containing a newline"
  echo "::add-mask::$exported_token"
  append_env CLOUDSMITH_API_KEY "$exported_token"
  append_env CLOUDSMITH_USERNAME "$credential_username"
fi

if [[ "$verify_auth" == "true" ]]; then
  # whoami prints its status to stdout. Some CLI builds exit 0 even on a 401,
  # so treat the failure marker in the output as authoritative too.
  if auth_output="$("$executable" whoami 2>&1)"; then
    auth_status=0
  else
    auth_status=$?
  fi
  printf '%s\n' "$auth_output"
  if [[ "$auth_status" -ne 0 ]] \
    || grep -qF 'Failed to retrieve your authentication status' <<< "$auth_output"; then
    fail "Authentication verification failed. Check the credentials passed to this action."
  fi
fi

{
  printf 'cli-version=%s\n' "$resolved_version"
  printf 'target=%s\n' "$target"
  printf 'cli-path=%s\n' "$executable"
  printf 'bin-directory=%s\n' "$bin_dir"
} >> "$GITHUB_OUTPUT"
[[ -z "$exported_token" ]] \
  || printf 'oidc-token=%s\n' "$exported_token" >> "$GITHUB_OUTPUT"

echo "Cloudsmith CLI $resolved_version is available at $executable"
