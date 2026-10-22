#!/usr/bin/env bash
# Downloads the third-party pieces the AdMob iOS bridge is built from, at pinned
# versions with checksums, into build/deps (git-ignored). Safe to re-run: anything
# already present and verified is skipped.
#
#   tools/fetch_ios_deps.sh
#
# Pinned:
#   Google Mobile Ads SDK 13.11.0  - from Google's official Swift package manifest
#   Google User Messaging Platform 3.1.0 - same
#   godot-cpp, branch 4.5 at a fixed commit (MIT) - extensions built for 4.5 run on 4.7
#   SCons 4.11.1 (MIT), in a local virtualenv - build tool only, never shipped
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEPS="$ROOT/build/deps"
mkdir -p "$DEPS"

GMA_VERSION="13.11.0"
GMA_URL="https://dl.google.com/googleadmobadssdk/310516d18f0d600c/googlemobileadsios-spm-13.11.0.zip"
GMA_SHA256="310516d18f0d600c9e45ed42b955a6b8ec52108d380f7cd8ed1e424e9d3fec22"

UMP_VERSION="3.1.0"
UMP_URL="https://dl.google.com/googleadmobadssdk/90fe6bf3b0f4ce0d/googleusermessagingplatformios-spm-3.1.0.zip"
UMP_SHA256="90fe6bf3b0f4ce0d0199628c0871de58b6f673375148b98d52348aecc86db231"

GODOT_CPP_REPO="https://github.com/godotengine/godot-cpp.git"
GODOT_CPP_COMMIT="27d9dd23c83871e0619fca5dc2cddfbfd69e926a" # branch 4.5

SCONS_VERSION="4.11.1"
SCONS_SHA256="454cef364348053422696e3d2ecb4fa593c96a624f955842eaaea64f95c8d11d"

# Each download goes into its own empty directory and is only unpacked after
# its checksum matches.
fetch_zip() { # name url sha256 expected-xcframework
	local name="$1" url="$2" sum="$3" framework="$4"
	local dir="$DEPS/$name"
	if [[ -d "$dir/$framework" && -f "$dir/.verified" ]]; then
		echo "ok    $name (already verified)"
		return
	fi
	rm -rf "$dir"
	mkdir -p "$dir"
	echo "get   $name"
	curl -fsSL "$url" -o "$dir/download.zip"
	local actual
	actual="$(shasum -a 256 "$dir/download.zip" | cut -d' ' -f1)"
	if [[ "$actual" != "$sum" ]]; then
		echo "Checksum mismatch for $name: expected $sum, got $actual" >&2
		rm -rf "$dir"
		exit 1
	fi
	(cd "$dir" && unzip -q download.zip && rm download.zip)
	if [[ ! -d "$dir/$framework" ]]; then
		echo "$name: $framework not found in the archive" >&2
		exit 1
	fi
	touch "$dir/.verified"
	echo "ok    $name"
}

fetch_zip "GoogleMobileAds-$GMA_VERSION" "$GMA_URL" "$GMA_SHA256" "GoogleMobileAds.xcframework"
fetch_zip "UserMessagingPlatform-$UMP_VERSION" "$UMP_URL" "$UMP_SHA256" "UserMessagingPlatform.xcframework"

if [[ "$(git -C "$DEPS/godot-cpp" rev-parse HEAD 2>/dev/null || true)" == "$GODOT_CPP_COMMIT" ]]; then
	echo "ok    godot-cpp ($GODOT_CPP_COMMIT)"
else
	rm -rf "$DEPS/godot-cpp"
	echo "get   godot-cpp"
	git init -q "$DEPS/godot-cpp"
	git -C "$DEPS/godot-cpp" fetch -q --depth 1 "$GODOT_CPP_REPO" "$GODOT_CPP_COMMIT"
	git -C "$DEPS/godot-cpp" checkout -q FETCH_HEAD
	echo "ok    godot-cpp"
fi

if [[ -x "$DEPS/venv/bin/scons" ]] && "$DEPS/venv/bin/scons" --version 2>/dev/null | grep -q "$SCONS_VERSION"; then
	echo "ok    scons $SCONS_VERSION"
else
	echo "get   scons $SCONS_VERSION"
	rm -rf "$DEPS/venv"
	python3 -m venv "$DEPS/venv"
	printf 'scons==%s --hash=sha256:%s\n' "$SCONS_VERSION" "$SCONS_SHA256" > "$DEPS/scons-requirements.txt"
	"$DEPS/venv/bin/pip" install -q --disable-pip-version-check --require-hashes -r "$DEPS/scons-requirements.txt"
	echo "ok    scons $SCONS_VERSION"
fi
