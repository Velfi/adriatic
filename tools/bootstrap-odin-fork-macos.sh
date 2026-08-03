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
# Atomic mkdir lock; heartbeat keeps active setup fresh, stale locks expire.
LOCK_PATH="$ROOT/.tools/bootstrap-odin-fork.lock"
LOCK_STALE_SECONDS=300
LOCK_HEARTBEAT_SECONDS=30

bootstrap_lock_cleanup() {
	if [ -n "${BOOTSTRAP_LOCK_HEARTBEAT_PID:-}" ]; then
		kill "$BOOTSTRAP_LOCK_HEARTBEAT_PID" 2>/dev/null || true
		wait "$BOOTSTRAP_LOCK_HEARTBEAT_PID" 2>/dev/null || true
	fi
	if [ -f "$LOCK_PATH/pid" ] && [ "$(cat "$LOCK_PATH/pid")" = "$$" ]; then
		rm -rf "$LOCK_PATH"
	fi
}

mkdir -p "$(dirname "$LOCK_PATH")"
while ! mkdir "$LOCK_PATH" 2>/dev/null; do
	now=$(date +%s)
	heartbeat=$(stat -f %m "$LOCK_PATH/heartbeat" 2>/dev/null || stat -f %m "$LOCK_PATH" 2>/dev/null || echo 0)
	if [ "$heartbeat" -gt 0 ] && [ $((now - heartbeat)) -ge "$LOCK_STALE_SECONDS" ]; then
		rm -rf "$LOCK_PATH"
		continue
	fi
	sleep 1
done
printf '%s\n' "$$" > "$LOCK_PATH/pid"
: > "$LOCK_PATH/heartbeat"
trap bootstrap_lock_cleanup EXIT
trap 'exit 1' HUP INT TERM
(
	while sleep "$LOCK_HEARTBEAT_SECONDS"; do
		if [ -f "$LOCK_PATH/pid" ] && [ "$(cat "$LOCK_PATH/pid")" = "$$" ]; then
			touch "$LOCK_PATH/heartbeat"
		else
			exit 0
		fi
	done
) &
BOOTSTRAP_LOCK_HEARTBEAT_PID=$!

if [ ! -d "$SOURCE_DIR/.git" ]; then
	mkdir -p "$(dirname "$SOURCE_DIR")"
	git clone "$ODIN_FORK_REPOSITORY" "$SOURCE_DIR"
fi

git -C "$SOURCE_DIR" fetch --quiet origin "$ODIN_FORK_COMMIT"
git -C "$SOURCE_DIR" checkout --quiet --detach "$ODIN_FORK_COMMIT"

if [ ! -x "$SOURCE_DIR/odin" ] || ! "$SOURCE_DIR/odin" version | grep -q "$ODIN_VERSION_OUTPUT"; then
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
