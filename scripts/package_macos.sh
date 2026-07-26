#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Adriatic"
BUNDLE_ID="${MACOS_BUNDLE_ID:-com.velfi.adriatic}"
VERSION="${VERSION:-0.1.0}"
SIGN_IDENTITY="${MACOS_CODESIGN_IDENTITY:-}"
SKIP_SIGN=0
SKIP_NOTARIZE=0

usage() {
	echo "Usage: scripts/package_macos.sh [--version VERSION] [--skip-sign] [--skip-notarize]"
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--version) VERSION="$2"; shift 2 ;;
		--skip-sign) SKIP_SIGN=1; shift ;;
		--skip-notarize) SKIP_NOTARIZE=1; shift ;;
		-h|--help) usage; exit 0 ;;
		*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
	esac
done

DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
FRAMEWORKS="$CONTENTS/Frameworks"
ARCHIVE="$DIST/$APP_NAME-macos.zip"
REAL_EXECUTABLE="adriatic-bin"
REAL_BINARY="$RESOURCES/$REAL_EXECUTABLE"

make -C "$ROOT" release ZELDA_ENGINE_ROOT="${ZELDA_ENGINE_ROOT:-$ROOT/../zelda-engine}"

rm -rf "$APP" "$ARCHIVE"
mkdir -p "$MACOS" "$RESOURCES" "$FRAMEWORKS"
cp "$ROOT/build/release/adriatic" "$REAL_BINARY"
chmod 755 "$REAL_BINARY"
cp -R "$ROOT/build/release/assets" "$RESOURCES/assets"
cp -R "$ROOT/build/release/shaders" "$RESOURCES/shaders"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$APP_NAME</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>$APP_NAME</string>
<key>CFBundleDisplayName</key><string>$APP_NAME</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

cat > "$ROOT/build/release/adriatic_launcher.c" <<'SOURCE'
#include <limits.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
int main(int argc, char **argv) {
	char path[PATH_MAX], resolved[PATH_MAX], contents[PATH_MAX], resources[PATH_MAX], target[PATH_MAX], loader[PATH_MAX], icd[PATH_MAX];
	uint32_t size = sizeof(path);
	if (_NSGetExecutablePath(path, &size) != 0 || realpath(path, resolved) == NULL) return 1;
	strncpy(contents, resolved, sizeof(contents));
	char *slash = strrchr(contents, '/'); if (!slash) return 1; *slash = 0;
	slash = strrchr(contents, '/'); if (!slash) return 1; *slash = 0;
	snprintf(resources, sizeof(resources), "%s/Resources", contents);
	snprintf(target, sizeof(target), "%s/Resources/adriatic-bin", contents);
	snprintf(loader, sizeof(loader), "%s/Frameworks/libvulkan.1.dylib", contents);
	snprintf(icd, sizeof(icd), "%s/vulkan/icd.d/MoltenVK_icd.json", resources);
	if (access(loader, R_OK) == 0) setenv("SDL_VULKAN_LIBRARY", loader, 1);
	if (access(icd, R_OK) == 0) setenv("VK_ICD_FILENAMES", icd, 1);
	if (chdir(resources) != 0) { perror("chdir"); return 1; }
	argv[0] = target;
	execv(target, argv);
	perror("execv");
	return 1;
}
SOURCE
cc "$ROOT/build/release/adriatic_launcher.c" -o "$MACOS/$APP_NAME"

copy_library() {
	local source="$1"
	[[ -f "$source" ]] || return 0
	cp -f "$source" "$FRAMEWORKS/$(basename "$source")"
	chmod 755 "$FRAMEWORKS/$(basename "$source")"
}

for spec in \
	"sdl3:lib/libSDL3.0.dylib" \
	"vulkan-loader:lib/libvulkan.1.dylib" \
	"molten-vk:lib/libMoltenVK.dylib"; do
	formula="${spec%%:*}"
	relative="${spec#*:}"
	prefix="$(brew --prefix "$formula" 2>/dev/null || true)"
	[[ -n "$prefix" ]] && copy_library "$prefix/$relative"
done
copy_library "${ZELDA_ENGINE_ROOT:-$ROOT/../zelda-engine}/third_party/jolt/libzelda_physics.dylib"
moltenvk_prefix="$(brew --prefix molten-vk 2>/dev/null || true)"
moltenvk_icd=""
for candidate in \
	"$moltenvk_prefix/etc/vulkan/icd.d/MoltenVK_icd.json" \
	"$moltenvk_prefix/share/vulkan/icd.d/MoltenVK_icd.json"; do
	if [[ -f "$candidate" ]]; then
		moltenvk_icd="$candidate"
		break
	fi
done
if [[ -n "$moltenvk_icd" ]]; then
	mkdir -p "$RESOURCES/vulkan/icd.d"
	sed 's#../../../lib/libMoltenVK#../../../Frameworks/libMoltenVK#' \
		"$moltenvk_icd" \
		> "$RESOURCES/vulkan/icd.d/MoltenVK_icd.json"
fi

# Pull every non-system dependency into Frameworks and rewrite its load path.
queue=("$REAL_BINARY")
while IFS= read -r -d '' library; do
	queue+=("$library")
done < <(find "$FRAMEWORKS" -type f -name '*.dylib' -print0)
while ((${#queue[@]})); do
	binary="${queue[0]}"
	queue=("${queue[@]:1}")
	while read -r dependency; do
		[[ -n "$dependency" ]] || continue
		case "$dependency" in /usr/lib/*|/System/Library/*) continue ;; esac
		case "$dependency" in
			@rpath/*) source="$FRAMEWORKS/${dependency#@rpath/}" ;;
			@loader_path/*) source="$(dirname "$binary")/${dependency#@loader_path/}" ;;
			@executable_path/*) source="$MACOS/${dependency#@executable_path/}" ;;
			*) source="$dependency" ;;
		esac
		[[ -f "$source" ]] || { echo "Unresolved dylib $dependency from $binary" >&2; exit 1; }
		name="$(basename "$source")"
		target="$FRAMEWORKS/$name"
		if [[ "$source" != "$target" && ! -f "$target" ]]; then
			copy_library "$source"
			queue+=("$target")
		fi
		install_name_tool -id "@rpath/$name" "$target" 2>/dev/null || true
		install_name_tool -change "$dependency" "@rpath/$name" "$binary"
	done < <(otool -L "$binary" | awk 'NR > 1 {print $1}')
done
install_name_tool -add_rpath "@executable_path/../Frameworks" "$REAL_BINARY" 2>/dev/null || true

if [[ "$SKIP_SIGN" == 0 ]]; then
	[[ -n "$SIGN_IDENTITY" ]] || { echo "MACOS_CODESIGN_IDENTITY is required" >&2; exit 1; }
	while IFS= read -r -d '' item; do
		codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$item"
	done < <(find "$FRAMEWORKS" -type f -print0)
	codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$REAL_BINARY"
	codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$MACOS/$APP_NAME"
	codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$APP"
	codesign --verify --deep --strict "$APP"
else
	# install_name_tool invalidates Homebrew's signatures. Ad-hoc signing keeps
	# unsigned CI artifacts launchable without implying a notarized identity.
	while IFS= read -r -d '' item; do
		codesign --force --sign - "$item"
	done < <(find "$FRAMEWORKS" -type f -print0)
	codesign --force --sign - "$REAL_BINARY"
	codesign --force --sign - "$MACOS/$APP_NAME"
	codesign --force --sign - "$APP"
	codesign --verify --deep --strict "$APP"
fi

ditto -c -k --keepParent "$APP" "$ARCHIVE"
if [[ "$SKIP_SIGN" == 0 && "$SKIP_NOTARIZE" == 0 ]]; then
	: "${APPLE_API_KEY_PATH:?Missing APPLE_API_KEY_PATH}"
	: "${APPLE_API_KEY:?Missing APPLE_API_KEY}"
	: "${APPLE_API_ISSUER:?Missing APPLE_API_ISSUER}"
	xcrun notarytool submit "$ARCHIVE" --key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY" --issuer "$APPLE_API_ISSUER" --wait
	xcrun stapler staple "$APP"
	xcrun stapler validate "$APP"
	ditto -c -k --keepParent "$APP" "$ARCHIVE"
fi
echo "Archive: $ARCHIVE"
