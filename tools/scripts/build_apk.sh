#!/usr/bin/env bash
#===============================================================================
# build_apk.sh [DIST_DIR]
#-------------------------------------------------------------------------------
# Builds the mkxp-z Android app (lib/mkxp-z/android) and copies the debug APK
# into DIST_DIR (default: dist/). The app does not contain the game: load
# dist/pokessentials-android.zip (from `make android`) through the app's
# slide-out menu, or push the .obb next to it to the device's OBB folder.
#
# Requirements: ANDROID_NDK_HOME (NDK r25+), the Android SDK (ANDROID_HOME or
# ANDROID_SDK_ROOT), JDK 11+, meson, ninja, cmake and autotools.
# Set ABIS (for example ABIS=arm64-v8a) to build fewer ABIs.
#===============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIST="${1:-$ROOT/dist}"
[[ "$DIST" = /* ]] || DIST="$ROOT/$DIST"
ANDROID_DIR="$ROOT/lib/mkxp-z/android"

die() { echo "build_apk: $*" >&2; exit 1; }

[[ -n "${ANDROID_NDK_HOME:-}" && -d "${ANDROID_NDK_HOME:-}" ]] ||
  die "set ANDROID_NDK_HOME to an Android NDK (r25 or newer). See docs/BUILDING.md."
[[ -n "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}" ]] ||
  die "set ANDROID_HOME (or ANDROID_SDK_ROOT) to your Android SDK. See docs/BUILDING.md."
command -v java >/dev/null 2>&1 || die "a JDK (11 or newer) is required."

cd "$ANDROID_DIR"
./build.sh
if [[ -x ./gradlew ]]; then
  ./gradlew assembleDebug
else
  command -v gradle >/dev/null 2>&1 || die "no gradlew and no gradle found; run 'gradle wrapper' in lib/mkxp-z/android once."
  gradle assembleDebug
fi

APK="$(find app/build/outputs/apk -name '*.apk' | head -n1)"
[[ -n "$APK" ]] || die "Gradle finished but no APK was found."
mkdir -p "$DIST"
cp "$APK" "$DIST/pokessentials-debug.apk"
echo "Wrote ${DIST#"$ROOT/"}/pokessentials-debug.apk"
