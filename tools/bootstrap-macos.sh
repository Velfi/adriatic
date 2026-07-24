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

brew install odinfmt "$LLVM_HOMEBREW_FORMULA"

case "$(uname -m)" in
	arm64) ODIN_ARCHIVE=$ODIN_MACOS_ARM64_ARCHIVE; ODIN_SHA256=$ODIN_MACOS_ARM64_SHA256; SLANG_ARCHIVE=$SLANG_MACOS_ARM64_ARCHIVE; SLANG_SHA256=$SLANG_MACOS_ARM64_SHA256 ;;
	x86_64) ODIN_ARCHIVE=$ODIN_MACOS_AMD64_ARCHIVE; ODIN_SHA256=$ODIN_MACOS_AMD64_SHA256; SLANG_ARCHIVE=$SLANG_MACOS_AMD64_ARCHIVE; SLANG_SHA256=$SLANG_MACOS_AMD64_SHA256 ;;
	*) echo "error: unsupported macOS architecture: $(uname -m)" >&2; exit 1 ;;
esac

ODIN_DIR="$ROOT/.tools/odin/$ODIN_VERSION"
SLANG_DIR="$ROOT/.tools/slang/$SLANG_VERSION"
DOWNLOAD_DIR="$ROOT/.tools/downloads"
mkdir -p "$DOWNLOAD_DIR"

if [ ! -x "$ODIN_DIR/odin" ]; then
	archive="$DOWNLOAD_DIR/$ODIN_ARCHIVE"
	curl -fL --retry 3 -o "$archive" "https://github.com/odin-lang/Odin/releases/download/$ODIN_VERSION/$ODIN_ARCHIVE"
	actual=$(shasum -a 256 "$archive" | awk '{print $1}')
	if [ "$actual" != "$ODIN_SHA256" ]; then
		echo "error: checksum mismatch for $archive" >&2
		exit 1
	fi
	stage=$(mktemp -d "${TMPDIR:-/tmp}/adriatic-odin.XXXXXX")
	trap 'rm -rf "$stage"' EXIT HUP INT TERM
	tar -xzf "$archive" -C "$stage"
	extracted=$(find "$stage" -type f -name odin -perm -111 | head -1)
	[ -n "$extracted" ] || { echo "error: Odin archive did not contain an executable" >&2; exit 1; }
	mkdir -p "$(dirname "$ODIN_DIR")"
	rm -rf "$ODIN_DIR"
	mv "$(dirname "$extracted")" "$ODIN_DIR"
fi

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
