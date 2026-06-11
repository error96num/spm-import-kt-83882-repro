#!/usr/bin/env bash
# Reproduces KT-84384: integrateLinkagePackage fails if xcode-select -p returns a symlink.
#
# The task derives Xcode sibling paths (Contents/Frameworks, Contents/SharedFrameworks)
# from the raw `xcode-select -p` output. When DEVELOPER_DIR points at a symlink,
# `xcode-select -p` echoes the symlink path verbatim and the generated mutatePbxproj
# binary tries to dlopen DevToolsCore from e.g. /tmp/Frameworks/... and crashes.
#
# Usage: ./repro-kt-84384.sh
set -euo pipefail
cd "$(dirname "$0")"

REAL_DEV_DIR="$(env -u DEVELOPER_DIR xcode-select -p)"
SYMLINK=/tmp/xcode-dev-symlink
ln -sfn "$REAL_DEV_DIR" "$SYMLINK"

echo "==> Control run (real DEVELOPER_DIR) — expected: SUCCESS"
git checkout -- iosApp/iosApp.xcodeproj/project.pbxproj
XCODEPROJ_PATH="$PWD/iosApp/iosApp.xcodeproj" ./gradlew :consumer:integrateLinkagePackage --console=plain -q \
    && echo "control: OK" || { echo "control run failed unexpectedly"; exit 1; }

echo
echo "==> Bug run (DEVELOPER_DIR=$SYMLINK, xcode-select -p prints the symlink) — expected: FAILURE"
git checkout -- iosApp/iosApp.xcodeproj/project.pbxproj
if DEVELOPER_DIR="$SYMLINK" XCODEPROJ_PATH="$PWD/iosApp/iosApp.xcodeproj" \
    ./gradlew :consumer:integrateLinkagePackage --console=plain -q; then
    echo "NOT REPRODUCED: task succeeded with symlinked DEVELOPER_DIR"
    exit 1
else
    echo "REPRODUCED: task fails with symlinked DEVELOPER_DIR"
    echo "(look for: Fatal error: dlopen(/tmp/Frameworks/DevToolsCore.framework/DevToolsCore ...)"
fi
