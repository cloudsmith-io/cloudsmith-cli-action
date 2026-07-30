#!/usr/bin/env sh
# Cloudsmith CLI standalone binary installer.
#
# Detects the target, verifies the release archive, and installs it into a
# versioned directory. Does not touch PATH or authenticate.
set -eu

PROGRAM="install.sh"
INSTALLER_USER_AGENT="cloudsmith-cli-install-script ($(uname -s 2>/dev/null || echo unknown); $(uname -m 2>/dev/null || echo unknown))"

# Where releases are downloaded from. Flags and CLOUDSMITH_CLI_* environment
# variables override the defaults; --manifest-url bypasses URL construction.
DOWNLOAD_BASE_URL="https://dl.cloudsmith.io/public"
DEFAULT_REPOSITORY="cloudsmith/cli"
MANIFEST_NAME_PREFIX="cloudsmith-cli-manifest"

REPOSITORY="${CLOUDSMITH_CLI_REPOSITORY:-$DEFAULT_REPOSITORY}"
REQUESTED_VERSION="${CLOUDSMITH_CLI_VERSION:-latest}"
INSTALL_ROOT="${CLOUDSMITH_CLI_INSTALL_ROOT:-}"
TARGET_OVERRIDE="${CLOUDSMITH_CLI_TARGET:-}"
OUTPUT_FILE="${CLOUDSMITH_CLI_OUTPUT_FILE:-}"
MANIFEST_URL="${CLOUDSMITH_CLI_MANIFEST_URL:-}"
ALLOW_INSECURE_URLS="${CLOUDSMITH_CLI_ALLOW_INSECURE_URLS:-false}"
FORCE="0"

WORK_DIR=""
LOCK_DIR=""

log() { printf '%s: %s\n' "$PROGRAM" "$*" >&2; }
die() { log "$*"; exit 1; }

usage() {
  cat <<'USAGE'
Usage: install.sh [options]

  --version VERSION       CLI version, or "latest"
  --install-root DIR      Versioned installation root
  --target TARGET         Override target detection
  --output-file FILE      Write key=value installation results
  --repository OWNER/REPO Cloudsmith public raw repository (advanced)
  --manifest-url URL      Override generated manifest URL (advanced/testing)
  --force                 Reinstall an existing matching version
  -h, --help              Show help
USAGE
}

require_value() {
  [ -n "${2-}" ] || die "$1 requires a value"
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --version) require_value "$1" "${2-}"; REQUESTED_VERSION="$2"; shift 2 ;;
      --install-root) require_value "$1" "${2-}"; INSTALL_ROOT="$2"; shift 2 ;;
      --target) require_value "$1" "${2-}"; TARGET_OVERRIDE="$2"; shift 2 ;;
      --output-file) require_value "$1" "${2-}"; OUTPUT_FILE="$2"; shift 2 ;;
      --repository) require_value "$1" "${2-}"; REPOSITORY="$2"; shift 2 ;;
      --manifest-url) require_value "$1" "${2-}"; MANIFEST_URL="$2"; shift 2 ;;
      --force) FORCE="1"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown option: $1" ;;
    esac
  done

  case "$REQUESTED_VERSION" in ''|.|..|*[!A-Za-z0-9._+-]*) die "invalid version: $REQUESTED_VERSION" ;; esac
  case "$REPOSITORY" in */*) ;; *) die "repository must be OWNER/REPOSITORY" ;; esac
  case "$REPOSITORY" in *[!A-Za-z0-9._/-]*) die "invalid repository: $REPOSITORY" ;; esac
}

default_install_root() {
  if [ -n "${XDG_DATA_HOME:-}" ]; then
    printf '%s\n' "$XDG_DATA_HOME/cloudsmith-cli"
  elif [ -n "${HOME:-}" ]; then
    printf '%s\n' "$HOME/.local/share/cloudsmith-cli"
  else
    die "HOME or XDG_DATA_HOME must be set unless --install-root is provided"
  fi
}

set_default_install_root() {
  [ -n "$INSTALL_ROOT" ] || INSTALL_ROOT="$(default_install_root)"
}

cleanup() {
  [ -z "$LOCK_DIR" ] || rmdir "$LOCK_DIR" 2>/dev/null || true
  [ -z "$WORK_DIR" ] || rm -rf "$WORK_DIR"
}

enable_signal_traps() {
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

require_https() {
  # Args: <url> <label>
  case "$1" in https://*) return 0 ;; esac
  [ "$ALLOW_INSECURE_URLS" = true ] || die "$2 must use HTTPS"
}

http_download() {
  url="$1"; output="$2"
  if command -v curl >/dev/null 2>&1; then
    if [ "$ALLOW_INSECURE_URLS" = true ]; then
      curl --fail --silent --show-error --location \
        --user-agent "$INSTALLER_USER_AGENT" \
        --retry 3 --retry-delay 1 --connect-timeout 20 --max-time 300 \
        --output "$output" "$url"
    else
      curl --fail --silent --show-error --location \
        --proto '=https' --proto-redir '=https' \
        --user-agent "$INSTALLER_USER_AGENT" \
        --retry 3 --retry-delay 1 --connect-timeout 20 --max-time 300 \
        --output "$output" "$url"
    fi
  elif command -v wget >/dev/null 2>&1; then
    if [ "$ALLOW_INSECURE_URLS" = true ]; then
      wget -q -T 300 -U "$INSTALLER_USER_AGENT" -O "$output" "$url"
    elif wget --help 2>&1 | grep -- '--https-only' >/dev/null 2>&1; then
      wget -q -T 300 --https-only -U "$INSTALLER_USER_AGENT" -O "$output" "$url"
    else
      die "secure downloads require curl or GNU wget with --https-only"
    fi
  else
    die "curl or wget is required"
  fi
}

sha256_file() {
  file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$file" | awk '{print $NF}'
  else
    die "sha256sum, shasum, or openssl is required"
  fi
}

check_required_tools() {
  case "$ARCHIVE_NAME" in
    *.tar.gz|*.tgz)
      command -v tar >/dev/null 2>&1 || die "tar is required"
      command -v gzip >/dev/null 2>&1 || die "gzip is required"
      ;;
    *.zip)
      command -v unzip >/dev/null 2>&1 || die "unzip is required"
      ;;
    *) die "unsupported archive format: $ARCHIVE_NAME" ;;
  esac

  if ! command -v sha256sum >/dev/null 2>&1 &&
     ! command -v shasum >/dev/null 2>&1 &&
     ! command -v openssl >/dev/null 2>&1; then
    die "sha256sum, shasum, or openssl is required"
  fi
}

manifest_value() {
  awk -F= -v wanted="$1" '
    $0 !~ /^[[:space:]]*#/ && $1 == wanted {
      sub(/^[^=]*=/, ""); sub(/\r$/, ""); print; exit
    }
  ' "$MANIFEST_FILE"
}

detect_target() {
  if [ -n "$TARGET_OVERRIDE" ]; then
    case "$TARGET_OVERRIDE" in .|..|*[!A-Za-z0-9._-]*) die "invalid target: $TARGET_OVERRIDE" ;; esac
    printf '%s\n' "$TARGET_OVERRIDE"
    return
  fi

  system="$(uname -s 2>/dev/null || true)"
  machine="$(uname -m 2>/dev/null || true)"
  case "$system" in
    Darwin)
      case "$machine" in
        arm64|aarch64) printf '%s\n' macos-arm64 ;;
        x86_64|amd64)
          # A translated shell reports x86_64 even when the host is Apple
          # silicon. Prefer the native CLI binary when Rosetta 2 is detected.
          if [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || true)" = 1 ]; then
            printf '%s\n' macos-arm64
          else
            printf '%s\n' macos-x86_64
          fi
          ;;
        *) die "unsupported macOS architecture: $machine" ;;
      esac
      ;;
    Linux)
      case "$machine" in
        x86_64|amd64) architecture=x86_64 ;;
        aarch64|arm64) architecture=aarch64 ;;
        *) die "unsupported Linux architecture: $machine" ;;
      esac
      if [ -f /etc/alpine-release ] || ls /lib/ld-musl-*.so.1 >/dev/null 2>&1; then
        libc=musl
      elif command -v getconf >/dev/null 2>&1 && getconf GNU_LIBC_VERSION >/dev/null 2>&1; then
        libc=gnu
      elif command -v ldd >/dev/null 2>&1; then
        ldd_output="$(ldd --version 2>&1 || true)"
        case "$ldd_output" in
          *musl*|*Musl*) libc=musl ;;
          *GLIBC*|*glibc*|*GNU\ libc*) libc=gnu ;;
          *) die "unable to determine Linux libc; pass --target" ;;
        esac
      else
        die "unable to determine Linux libc; pass --target"
      fi
      printf '%s\n' "linux-${architecture}-${libc}"
      ;;
    MINGW*|MSYS*|CYGWIN*) printf '%s\n' windows-x86_64 ;;
    *) die "unsupported operating system: ${system:-unknown}" ;;
  esac
}

fetch_manifest() {
  MANIFEST_FILE="$WORK_DIR/manifest.txt"
  if [ -z "$MANIFEST_URL" ]; then
    MANIFEST_URL="$DOWNLOAD_BASE_URL/$REPOSITORY/raw/names/$MANIFEST_NAME_PREFIX-$TARGET/versions/$REQUESTED_VERSION/manifest.txt"
  fi
  require_https "$MANIFEST_URL" "manifest URL"
  log "fetching release manifest"
  http_download "$MANIFEST_URL" "$MANIFEST_FILE"
}

validate_manifest() {
  SCHEMA="$(manifest_value schema)"
  RESOLVED_VERSION="$(manifest_value version)"
  MANIFEST_TARGET="$(manifest_value target)"
  ARCHIVE_NAME="$(manifest_value archive)"
  ARCHIVE_URL="$(manifest_value url)"
  EXPECTED_SHA256="$(manifest_value sha256 | tr 'A-F' 'a-f')"

  [ "$SCHEMA" = 1 ] || die "unsupported manifest schema: ${SCHEMA:-missing}"
  case "$RESOLVED_VERSION" in ''|.|..|*[!A-Za-z0-9._+-]*) die "manifest contains an invalid version" ;; esac
  [ "$MANIFEST_TARGET" = "$TARGET" ] || die "manifest target '$MANIFEST_TARGET' does not match '$TARGET'"
  [ "$REQUESTED_VERSION" = latest ] || [ "$REQUESTED_VERSION" = "$RESOLVED_VERSION" ] || die "manifest resolved '$RESOLVED_VERSION', expected '$REQUESTED_VERSION'"
  case "$ARCHIVE_NAME" in ''|*/*|*\\*) die "manifest contains an invalid archive name" ;; esac
  [ -n "$ARCHIVE_URL" ] || die "manifest is missing url"
  case "$EXPECTED_SHA256" in ''|*[!0-9a-f]*) die "manifest contains an invalid SHA-256" ;; esac
  [ "${#EXPECTED_SHA256}" -eq 64 ] || die "manifest SHA-256 must be 64 hexadecimal characters"
  require_https "$ARCHIVE_URL" "archive URL"
}

prepare_destination() {
  FINAL_PARENT="$INSTALL_ROOT/$RESOLVED_VERSION/$TARGET"
  BIN_DIR="$FINAL_PARENT/cloudsmith"
  case "$TARGET" in windows-*) BIN="$BIN_DIR/cloudsmith.exe" ;; *) BIN="$BIN_DIR/cloudsmith" ;; esac
  METADATA_FILE="$BIN_DIR/.cloudsmith-installation"
  lock_dir="$FINAL_PARENT/.install.lock"
  mkdir -p "$FINAL_PARENT"

  waited=0
  while :; do
    pending_signal_status=0
    trap 'pending_signal_status=130' INT
    trap 'pending_signal_status=143' TERM

    # Defer cancellation until ownership is known. The subshell prevents a
    # process-group signal from killing mkdir after it creates the lock.
    if (trap '' INT TERM; CLOUDSMITH_CLI_LOCK_OWNER_PID=$$ mkdir "$lock_dir") 2>/dev/null; then
      LOCK_DIR="$lock_dir"
      enable_signal_traps
      [ "$pending_signal_status" -eq 0 ] || exit "$pending_signal_status"
      break
    fi
    enable_signal_traps
    [ "$pending_signal_status" -eq 0 ] || exit "$pending_signal_status"

    [ "$waited" -lt 120 ] || die "timed out waiting for installation lock: $lock_dir"
    sleep 1
    waited=$((waited + 1))
  done
}

reuse_existing_install() {
  [ "$FORCE" = 0 ] || return 1
  [ -f "$BIN" ] || return 1
  [ -f "$METADATA_FILE" ] || return 1
  installed_sha="$(awk -F= '$1 == "archive_sha256" {sub(/^[^=]*=/, ""); print; exit}' "$METADATA_FILE")"
  [ "$installed_sha" = "$EXPECTED_SHA256" ] || return 1
  version_output="$("$BIN" --version 2>/dev/null)" || return 1
  printf '%s\n' "$version_output" | grep -Fxq "CLI Package Version: $RESOLVED_VERSION" || return 1
  log "reusing verified installation $RESOLVED_VERSION at $BIN_DIR"
}

download_archive() {
  ARCHIVE_FILE="$WORK_DIR/$ARCHIVE_NAME"
  log "downloading Cloudsmith CLI $RESOLVED_VERSION"
  http_download "$ARCHIVE_URL" "$ARCHIVE_FILE"
  ACTUAL_SHA256="$(sha256_file "$ARCHIVE_FILE" | tr 'A-F' 'a-f')"
  [ "$ACTUAL_SHA256" = "$EXPECTED_SHA256" ] || die "archive checksum mismatch"
  log "archive checksum verified"
}

validate_archive_listing() {
  # Relative symlinks are expected (macOS bundles ship Python.framework links);
  # absolute or ..-escaping link targets and hardlinks are rejected.
  listing_file="$1"
  while IFS= read -r listing || [ -n "$listing" ]; do
    [ -n "$listing" ] || continue
    case "$listing" in
      h*) die "archive contains an unsupported link entry" ;;
      l*)
        link_target="${listing##* -> }"
        [ "$link_target" != "$listing" ] || die "archive contains an unsupported link entry"
        case "$link_target" in /*|*\\*) die "archive contains an unsafe link entry: $link_target" ;; esac
        case "/$link_target/" in */../*) die "archive contains an unsafe link entry: $link_target" ;; esac
        ;;
    esac
  done < "$listing_file"
}

validate_archive_entries() {
  case "$ARCHIVE_FILE" in
    *.tar.gz|*.tgz)
      tar -tvzf "$ARCHIVE_FILE" > "$WORK_DIR/archive-listing.txt"
      validate_archive_listing "$WORK_DIR/archive-listing.txt"
      tar -tzf "$ARCHIVE_FILE" > "$WORK_DIR/archive-entries.txt"
      ;;
    *.zip)
      unzip -Z -l "$ARCHIVE_FILE" > "$WORK_DIR/archive-listing.txt"
      validate_archive_listing "$WORK_DIR/archive-listing.txt"
      unzip -Z1 "$ARCHIVE_FILE" > "$WORK_DIR/archive-entries.txt"
      ;;
    *) die "unsupported archive format: $ARCHIVE_FILE" ;;
  esac

  while IFS= read -r entry || [ -n "$entry" ]; do
    [ -n "$entry" ] || continue
    case "$entry" in /*|*\\*|[A-Za-z]:*) die "unsafe archive entry: $entry" ;; esac
    case "/$entry/" in */../*) die "unsafe archive entry: $entry" ;; esac
    case "$entry" in cloudsmith|cloudsmith/|cloudsmith/*) ;; *) die "unexpected archive entry: $entry" ;; esac
  done < "$WORK_DIR/archive-entries.txt"
}

stage_archive() {
  validate_archive_entries

  EXTRACT_DIR="$WORK_DIR/extract"
  mkdir -p "$EXTRACT_DIR"
  case "$ARCHIVE_FILE" in
    *.tar.gz|*.tgz) tar -xzf "$ARCHIVE_FILE" -C "$EXTRACT_DIR" ;;
    *.zip) unzip -q "$ARCHIVE_FILE" -d "$EXTRACT_DIR" ;;
  esac

  STAGED_DIR="$EXTRACT_DIR/cloudsmith"
  case "$TARGET" in windows-*) STAGED_BIN="$STAGED_DIR/cloudsmith.exe" ;; *) STAGED_BIN="$STAGED_DIR/cloudsmith" ;; esac
  [ -f "$STAGED_BIN" ] || die "archive does not contain the expected executable"
  [ ! -L "$STAGED_BIN" ] || die "archive contains an unsupported link entry"
  chmod +x "$STAGED_BIN" 2>/dev/null || true
  version_output="$("$STAGED_BIN" --version 2>&1)" || die "downloaded executable failed validation"
  printf '%s\n' "$version_output" | grep -Fxq "CLI Package Version: $RESOLVED_VERSION" \
    || die "downloaded executable did not report CLI version $RESOLVED_VERSION"
  log "validated CLI version $RESOLVED_VERSION"

  {
    printf 'schema=1\nversion=%s\ntarget=%s\narchive_sha256=%s\nmanifest_url=%s\n' \
      "$RESOLVED_VERSION" "$TARGET" "$EXPECTED_SHA256" "$MANIFEST_URL"
  } > "$STAGED_DIR/.cloudsmith-installation"
}

activate_staged_install() {
  TEMP_FINAL="$FINAL_PARENT/.cloudsmith.new.$$"
  OLD_FINAL="$FINAL_PARENT/.cloudsmith.old.$$"
  rm -rf "$TEMP_FINAL" "$OLD_FINAL"
  mv "$STAGED_DIR" "$TEMP_FINAL"
  [ ! -e "$BIN_DIR" ] || mv "$BIN_DIR" "$OLD_FINAL"
  if ! mv "$TEMP_FINAL" "$BIN_DIR"; then
    [ ! -e "$OLD_FINAL" ] || mv "$OLD_FINAL" "$BIN_DIR" 2>/dev/null || true
    die "failed to activate the staged installation"
  fi
  rm -rf "$OLD_FINAL"
  log "installed Cloudsmith CLI $RESOLVED_VERSION to $BIN_DIR"
}

write_result() {
  if [ -n "$OUTPUT_FILE" ]; then
    mkdir -p "$(dirname "$OUTPUT_FILE")"
    {
      printf 'version=%s\n' "$RESOLVED_VERSION"
      printf 'target=%s\n' "$TARGET"
      printf 'bin_dir=%s\n' "$BIN_DIR"
      printf 'executable=%s\n' "$BIN"
    } > "$OUTPUT_FILE"
  else
    printf 'version=%s\n' "$RESOLVED_VERSION"
    printf 'target=%s\n' "$TARGET"
    printf 'bin_dir=%s\n' "$BIN_DIR"
    printf 'executable=%s\n' "$BIN"
  fi
}

main() {
  TARGET="$(detect_target)"
  log "detected target $TARGET"
  mkdir -p "$INSTALL_ROOT/.tmp"
  WORK_DIR="$(mktemp -d "$INSTALL_ROOT/.tmp/install.XXXXXX")"

  fetch_manifest
  validate_manifest
  prepare_destination

  if reuse_existing_install; then
    write_result
    return 0
  fi

  check_required_tools
  download_archive
  stage_archive
  activate_staged_install
  write_result
}

trap cleanup EXIT
enable_signal_traps

parse_args "$@"
set_default_install_root
main
