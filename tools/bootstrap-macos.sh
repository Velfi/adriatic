#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

if [ "$(uname -s)" != "Darwin" ]; then
	echo "error: tools/bootstrap-macos.sh only supports macOS" >&2
	exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
	echo "error: Homebrew is required: https://brew.sh" >&2
	exit 1
fi

# shellcheck disable=SC1091
. "$ROOT/toolchain.mk"

brew install "$LLVM_HOMEBREW_FORMULA"

case "$(uname -m)" in
	arm64) SLANG_ARCHIVE=$SLANG_MACOS_ARM64_ARCHIVE; SLANG_SHA256=$SLANG_MACOS_ARM64_SHA256 ;;
	x86_64) SLANG_ARCHIVE=$SLANG_MACOS_AMD64_ARCHIVE; SLANG_SHA256=$SLANG_MACOS_AMD64_SHA256 ;;
	*) echo "error: unsupported macOS architecture: $(uname -m)" >&2; exit 1 ;;
esac

SLANG_DIR="$ROOT/.tools/slang/$SLANG_VERSION"
DOWNLOAD_DIR="$ROOT/.tools/downloads"
mkdir -p "$DOWNLOAD_DIR"

if [ ! -x "$SLANG_DIR/slangc" ]; then
	archive="$DOWNLOAD_DIR/$SLANG_ARCHIVE"
	curl -fL --retry 3 -o "$archive" "https://github.com/shader-slang/slang/releases/download/$SLANG_VERSION/$SLANG_ARCHIVE"
	actual=$(shasum -a 256 "$archive" | awk '{print $1}')
	if [ "$actual" != "$SLANG_SHA256" ]; then
		echo "error: checksum mismatch for $archive" >&2
		exit 1
	fi
	stage=$(mktemp -d "${TMPDIR:-/tmp}/adriatic-slang.XXXXXX")
	trap 'rm -rf "$stage"' EXIT HUP INT TERM
	unzip -q "$archive" -d "$stage"
	extracted=$(find "$stage" -type f -name slangc -perm -111 | head -1)
	[ -n "$extracted" ] || { echo "error: Slang archive did not contain an executable" >&2; exit 1; }
	mkdir -p "$(dirname "$SLANG_DIR")"
	rm -rf "$SLANG_DIR"
	mv "$stage" "$SLANG_DIR"
	trap - EXIT HUP INT TERM
fi

echo "Bootstrap complete. Run: make doctor"
