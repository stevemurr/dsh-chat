#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="release"
RUN_APP=false

usage() {
    cat <<'USAGE'
Usage: Scripts/build-app.sh [--debug | --release] [--run]

Build DSH Chat.app in dist/ and sign it for local use.
The default configuration is release. Add --run to launch the finished app.
USAGE
}

for argument in "$@"; do
    case "$argument" in
        --debug | debug) CONFIGURATION="debug" ;;
        --release | release) CONFIGURATION="release" ;;
        --run) RUN_APP=true ;;
        --help | -h) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$argument" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
    printf 'DSH Chat requires macOS 15 or later.\n' >&2
    exit 1
fi

if [[ ! -d "$ROOT_DIR/../dsh-swift" ]]; then
    printf 'Missing local SDK checkout: %s/../dsh-swift\n' "$ROOT_DIR" >&2
    printf 'Clone dsh-swift beside this repository before building.\n' >&2
    exit 1
fi

# Keep generated caches inside the checkout, including in restricted build environments.
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/ModuleCache"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/ModuleCache"
BUILD_OPTIONS=(--package-path "$ROOT_DIR" --configuration "$CONFIGURATION"
    --cache-path "$ROOT_DIR/.build/cache"
    --config-path "$ROOT_DIR/.build/configuration"
    --security-path "$ROOT_DIR/.build/security")
mkdir -p "$ROOT_DIR/.build/ModuleCache" "$ROOT_DIR/.build/cache" \
    "$ROOT_DIR/.build/configuration" "$ROOT_DIR/.build/security"
swift build "${BUILD_OPTIONS[@]}" --product DSHChat
BIN_DIR="$(swift build "${BUILD_OPTIONS[@]}" --show-bin-path)"

if [[ ! -f "$ROOT_DIR/Resources/AppIcon.icns" ]]; then
    swift -module-cache-path "$ROOT_DIR/.build/ModuleCache" \
        "$ROOT_DIR/Scripts/generate-icon.swift" "$ROOT_DIR/Resources/AppIcon.icns"
fi

APP_PATH="$ROOT_DIR/dist/DSH Chat.app"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN_DIR/DSHChat" "$APP_PATH/Contents/MacOS/DSHChat"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP_PATH/Contents/PkgInfo"
codesign --force --sign - "$APP_PATH"
codesign --verify --strict "$APP_PATH"

printf '\nBuilt %s (%s).\n' "$APP_PATH" "$CONFIGURATION"
if "$RUN_APP"; then
    if [[ -n "${DSH_HOME:-}" ]]; then
        open --env "DSH_HOME=$DSH_HOME" "$APP_PATH"
    else
        open "$APP_PATH"
    fi
fi
