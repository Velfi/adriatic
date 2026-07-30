#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

if [ "$(uname -s)" != "Darwin" ]; then
	echo "error: tools/bootstrap-ols-fork-macos.sh only supports macOS" >&2
	exit 1
fi

# shellcheck disable=SC1091
. "$ROOT/toolchain.mk"

command -v git >/dev/null 2>&1 || { echo "error: git is required" >&2; exit 1; }

ODIN_DIR="$ROOT/.tools/odin/$ODIN_FORK_VERSION"
SOURCE_DIR="$ROOT/.tools/ols/catermujo-src"
INSTALL_DIR="$ROOT/.tools/ols/$OLS_FORK_VERSION"

if [ ! -x "$ODIN_DIR/odin" ]; then
	echo "error: locked Odin is missing; run make bootstrap-fork first" >&2
	exit 1
fi

if [ ! -d "$SOURCE_DIR/.git" ]; then
	mkdir -p "$(dirname "$SOURCE_DIR")"
	git clone "$OLS_FORK_REPOSITORY" "$SOURCE_DIR"
fi

git -C "$SOURCE_DIR" fetch --quiet origin "$OLS_FORK_COMMIT"
git -C "$SOURCE_DIR" checkout --quiet --detach "$OLS_FORK_COMMIT"

if [ ! -x "$INSTALL_DIR/odinfmt" ]; then
	(
		cd "$SOURCE_DIR"
		PATH="$ODIN_DIR:$PATH" ./odinfmt.sh
	)
	mkdir -p "$INSTALL_DIR"
	cp "$SOURCE_DIR/odinfmt" "$INSTALL_DIR/odinfmt"
	chmod +x "$INSTALL_DIR/odinfmt"
fi

echo "Installed catermujo/ols odinfmt: $INSTALL_DIR/odinfmt"
