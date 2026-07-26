#!/usr/bin/env bash
#
# Tag and start an Adriatic release.
#
# Usage:
#   scripts/release.sh <version>
#
# Example:
#   scripts/release.sh 0.2.0
#   scripts/release.sh 0.3.0-beta.1
#
# This verifies that main is clean and synchronized with origin, creates an
# annotated v<version> tag, and optionally pushes it to trigger the Release
# GitHub Actions workflow.

set -euo pipefail

if [[ $# -ne 1 ]]; then
	echo "usage: $0 <version>   (e.g. $0 0.2.0)" >&2
	exit 1
fi

VERSION="$1"
TAG="v${VERSION}"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
	echo "error: '$VERSION' is not a valid semver version (expected MAJOR.MINOR.PATCH[-pre])" >&2
	exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$BRANCH" != "main" ]]; then
	echo "error: must be on 'main' branch (currently on '$BRANCH')" >&2
	exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
	echo "error: working tree has uncommitted changes" >&2
	git status --short >&2
	exit 1
fi

if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
	echo "error: tag ${TAG} already exists locally" >&2
	exit 1
fi

git fetch --tags origin >/dev/null
if git ls-remote --exit-code --tags origin "refs/tags/${TAG}" >/dev/null 2>&1; then
	echo "error: tag ${TAG} already exists on origin" >&2
	exit 1
fi

git fetch origin main >/dev/null
LOCAL="$(git rev-parse HEAD)"
REMOTE="$(git rev-parse refs/remotes/origin/main)"
if [[ "$LOCAL" != "$REMOTE" ]]; then
	echo "error: local main is not in sync with origin/main" >&2
	echo "  local:  $LOCAL" >&2
	echo "  remote: $REMOTE" >&2
	exit 1
fi

git tag -a "${TAG}" -m "Adriatic ${TAG}"

echo
echo "About to push the following tag to origin:"
echo "  - tag: ${TAG} at $(git rev-parse --short HEAD)"
echo
read -r -p "Push now? [y/N] " reply
case "$reply" in
	[yY]|[yY][eE][sS])
		git push origin "${TAG}"
		echo
		echo "Pushed. The release workflow should now be running:"
		echo "  https://github.com/Velfi/adriatic/actions/workflows/release.yml"
		;;
	*)
		echo "Skipped push. To finish the release later, run:"
		echo "  git push origin ${TAG}"
		echo "To undo locally, run: git tag -d ${TAG}"
		;;
esac
