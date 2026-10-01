#!/usr/bin/env bash
# Pins the default cli-version in action.yml to a new Cloudsmith CLI release
# and records the change as a release of the action in CHANGELOG.md. The
# release is a patch release, or a minor release that also includes the
# entries under [Unreleased] when there are any.
# Prints the new action version, or nothing when the version is already pinned.
# Usage: scripts/bump-cli-version.sh CLI_VERSION
set -euo pipefail

cli_version="${1:-}"
[[ "$cli_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || { echo "usage: $0 MAJOR.MINOR.PATCH" >&2; exit 1; }

pinned_version="$(awk '
  /^  cli-version:/ { in_cli_version = 1 }
  in_cli_version && /^    default:/ { gsub(/"/, "", $2); print $2; exit }
' action.yml)"
[[ -n "$pinned_version" ]] || { echo "no cli-version default in action.yml" >&2; exit 1; }
if [[ "$pinned_version" == "$cli_version" ]]; then
  echo "action.yml already pins Cloudsmith CLI $cli_version" >&2
  exit 0
fi

released_version="$(sed -n 's/^## \[\([0-9]*\.[0-9]*\.[0-9]*\)\].*/\1/p' CHANGELOG.md | head -n 1)"
[[ -n "$released_version" ]] || { echo "no released version in CHANGELOG.md" >&2; exit 1; }
unreleased_changes="$(awk '
  /^## \[/ { in_unreleased = ($0 == "## [Unreleased]"); next }
  in_unreleased && $0 != "" && $0 != "---"
' CHANGELOG.md)"
IFS=. read -r major minor patch <<< "$released_version"
if [[ -n "$unreleased_changes" ]]; then
  action_version="$major.$(( minor + 1 )).0"
else
  action_version="$major.$minor.$(( patch + 1 ))"
fi

awk -v cli_version="$cli_version" '
  /^  cli-version:/ { in_cli_version = 1 }
  in_cli_version && /^    default:/ { sub(/".*"/, "\"" cli_version "\""); in_cli_version = 0 }
  { print }
' action.yml > action.yml.new
mv action.yml.new action.yml

awk -v action_version="$action_version" -v cli_version="$cli_version" -v today="$(date -u +%Y-%m-%d)" '
  inserted && $0 != "" { print "" }
  { inserted = 0; print }
  previous == "## [Unreleased]" && $0 == "---" {
    inserted = 1
    print ""
    print "## [" action_version "] - " today
    print "---"
    print "### Changed"
    print ""
    print "- Pin the default `cli-version` to Cloudsmith CLI " cli_version "."
  }
  { previous = $0 }
' CHANGELOG.md > CHANGELOG.md.new
mv CHANGELOG.md.new CHANGELOG.md

echo "$action_version"
