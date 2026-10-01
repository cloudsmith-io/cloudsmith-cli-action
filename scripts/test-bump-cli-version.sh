#!/usr/bin/env bash
set -euo pipefail

bump_script="$(cd "$(dirname "$0")" && pwd)/bump-cli-version.sh"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
today="$(date -u +%Y-%m-%d)"

cat > "$test_root/action.yml" <<'EOF'
inputs:
  cli-version:
    description: "Cloudsmith CLI version to install."
    required: false
    default: "1.27.0"
  install-directory:
    default: ""
EOF

cat > "$test_root/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]
---
### Fixed

- An unreleased fix.

## [3.2.0] - 2026-10-01
---
### Changed

- An earlier change.
EOF

cat > "$test_root/expected-CHANGELOG.md" <<EOF
# Changelog

## [Unreleased]
---

## [3.3.0] - $today
---
### Changed

- Pin the default \`cli-version\` to Cloudsmith CLI 1.28.0.

### Fixed

- An unreleased fix.

## [3.2.0] - 2026-10-01
---
### Changed

- An earlier change.
EOF

sed 's/default: "1.27.0"/default: "1.28.0"/' "$test_root/action.yml" > "$test_root/expected-action.yml"

cd "$test_root"

# Unreleased changes make the CLI bump a minor release that includes them.
test "$(bash "$bump_script" 1.28.0)" = "3.3.0"
diff -u expected-action.yml action.yml
diff -u expected-CHANGELOG.md CHANGELOG.md

# With no unreleased changes, the CLI bump is a patch release.
test "$(bash "$bump_script" 1.29.0)" = "3.3.1"
sed -i.bak 's/default: "1.28.0"/default: "1.29.0"/' expected-action.yml
diff -u expected-action.yml action.yml
grep -Fx "## [3.3.1] - $today" CHANGELOG.md
grep -Fx -- "- Pin the default \`cli-version\` to Cloudsmith CLI 1.29.0." CHANGELOG.md

# The version that is already pinned changes nothing.
cp CHANGELOG.md expected-CHANGELOG.md
test -z "$(bash "$bump_script" 1.29.0)"
diff -u expected-action.yml action.yml
diff -u expected-CHANGELOG.md CHANGELOG.md

# A version older than the pinned version changes nothing.
test -z "$(bash "$bump_script" 1.28.5)"
diff -u expected-action.yml action.yml
diff -u expected-CHANGELOG.md CHANGELOG.md

# A version that is not MAJOR.MINOR.PATCH is rejected.
if bash "$bump_script" latest 2> /dev/null; then
  echo "expected 'latest' to be rejected" >&2
  exit 1
fi
diff -u expected-action.yml action.yml

echo "bump-cli-version tests passed"
