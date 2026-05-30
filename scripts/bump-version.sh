#!/usr/bin/env bash
# bump-version.sh — bump VERSION and seed a CHANGELOG section, keeping the two
# in sync (the release workflow and smoke test both assert a `## [VERSION]`
# heading exists). Does NOT commit or tag — it just edits the files and prints
# the next steps.
#
# Usage:
#   scripts/bump-version.sh patch        # 0.2.0 -> 0.2.1
#   scripts/bump-version.sh minor        # 0.2.0 -> 0.3.0
#   scripts/bump-version.sh major        # 0.2.0 -> 1.0.0
#   scripts/bump-version.sh 1.2.3        # set explicitly
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

arg="${1:-}"
cur="$(tr -d '[:space:]' < VERSION)"

case "$arg" in
  major|minor|patch)
    IFS=. read -r ma mi pa <<<"$cur"
    case "$arg" in
      major) ma=$((ma + 1)); mi=0; pa=0 ;;
      minor) mi=$((mi + 1)); pa=0 ;;
      patch) pa=$((pa + 1)) ;;
    esac
    new="$ma.$mi.$pa" ;;
  '')
    echo "usage: bump-version.sh <major|minor|patch|X.Y.Z>" >&2; exit 2 ;;
  *)
    new="$arg"
    echo "$new" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' \
      || { echo "invalid version: '$new' (want X.Y.Z)" >&2; exit 2; } ;;
esac

if grep -q "## \[$new\]" CHANGELOG.md; then
  echo "CHANGELOG already has a [$new] section; leaving it untouched." >&2
else
  date="$(date -u +%Y-%m-%d)"
  tmp="$(mktemp)"
  # Insert a fresh section just before the first existing release heading.
  awk -v v="$new" -v d="$date" '
    !seeded && /^## \[/ {
      print "## [" v "] - " d "\n";
      print "### Added\n";
      print "### Changed\n";
      print "### Fixed\n";
      seeded = 1
    }
    { print }
  ' CHANGELOG.md > "$tmp"
  mv "$tmp" CHANGELOG.md
fi

printf '%s\n' "$new" > VERSION

echo "bumped VERSION: $cur -> $new"
echo "next:"
echo "  1. fill in CHANGELOG.md under [$new]"
echo "  2. make check"
echo "  3. git commit -am \"release: v$new\""
echo "  4. git tag -a \"v$new\" -m \"v$new\" && git push --follow-tags"
