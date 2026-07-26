#!/usr/bin/env bash
#
# Move a release tag to the current HEAD and force-push only that tag to origin.
#
# Usage:
#   scripts/retag-head.sh <version>
#
# This is intentionally explicit because rewriting a published tag replaces
# the commit used by the release workflow.

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

if [[ -n "$(git status --porcelain)" ]]; then
	echo "error: working tree has uncommitted changes" >&2
	git status --short >&2
	exit 1
fi

if ! git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null &&
	! git ls-remote --exit-code --tags origin "refs/tags/${TAG}" >/dev/null 2>&1; then
	echo "error: tag ${TAG} does not exist locally or on origin" >&2
	exit 1
fi

echo "This will move ${TAG} to HEAD ($(git rev-parse --short HEAD)) and force-push it."
read -r -p "Continue? [y/N] " reply
case "$reply" in
	[yY]|[yY][eE][sS]) ;;
	*)
		echo "Cancelled."
		exit 0
		;;
esac

git tag -f -a "${TAG}" -m "Adriatic ${TAG}"
echo "Tagged ${TAG} at $(git rev-parse --short HEAD)"

git push origin "refs/tags/${TAG}" --force
