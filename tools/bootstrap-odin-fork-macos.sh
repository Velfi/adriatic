#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

if [ "$(uname -s)" != "Darwin" ]; then
	echo "error: tools/bootstrap-odin-fork-macos.sh only supports macOS" >&2
	exit 1
fi

# shellcheck disable=SC1091
. "$ROOT/toolchain.mk"

command -v git >/dev/null 2>&1 || { echo "error: git is required" >&2; exit 1; }
command -v make >/dev/null 2>&1 || { echo "error: make is required" >&2; exit 1; }

SOURCE_DIR="$ROOT/.tools/odin/catermujo-src"
INSTALL_DIR="$ROOT/.tools/odin/$ODIN_FORK_VERSION"

if [ ! -d "$SOURCE_DIR/.git" ]; then
	mkdir -p "$(dirname "$SOURCE_DIR")"
	git clone "$ODIN_FORK_REPOSITORY" "$SOURCE_DIR"
fi

git -C "$SOURCE_DIR" fetch --quiet origin "$ODIN_FORK_COMMIT"
git -C "$SOURCE_DIR" checkout --quiet --detach "$ODIN_FORK_COMMIT"

if [ ! -x "$SOURCE_DIR/odin" ]; then
	(
		cd "$SOURCE_DIR"
		./build_odin.sh release-native
	)
fi

mkdir -p "$INSTALL_DIR"
cp "$SOURCE_DIR/odin" "$INSTALL_DIR/odin"
chmod +x "$INSTALL_DIR/odin"
ln -sfn ../catermujo-src/base "$INSTALL_DIR/base"
ln -sfn ../catermujo-src/core "$INSTALL_DIR/core"
ln -sfn ../catermujo-src/vendor "$INSTALL_DIR/vendor"

actual=$("$INSTALL_DIR/odin" version)
case "$actual" in
	*"$ODIN_VERSION_OUTPUT"*) ;;
	*) echo "error: installed Odin reports '$actual', expected '$ODIN_VERSION_OUTPUT'" >&2; exit 1 ;;
esac

echo "Installed catermujo/Odin: $actual"
