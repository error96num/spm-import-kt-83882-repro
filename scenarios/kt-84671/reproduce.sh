#!/usr/bin/env bash
#
# Reproduces KT-84671: with a *relative* XCODEPROJ_PATH, integrateLinkagePackage
# resolves the synthetic linkage package root against the *subproject* directory
# (:consumer), while the pbxproj mutation resolves the same env var against the
# Gradle invocation working directory. The two disagree whenever the subproject
# dir != the working directory, so the synthetic package is generated in the
# wrong place and the XCLocalSwiftPackageReference written into the pbxproj
# dangles.
#
# https://youtrack.jetbrains.com/issue/KT-84671
#
# Usage: ./scenarios/kt-84671/reproduce.sh
# (run from the repo root; requires macOS + Xcode)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d /tmp/kt-84671.XXXXXX)"
echo "Workspace: $WORK"

# Layout from the issue description:
#   $WORK/root/iosApp/iosApp.xcodeproj   <- Xcode app, OUTSIDE the Gradle project
#   $WORK/root/kmp/                      <- Gradle project (this repo, minus iosApp)
mkdir -p "$WORK/root"
rsync -a --exclude '.git' --exclude '.gradle' --exclude 'build' \
    "$REPO_ROOT/" "$WORK/root/kmp/"
mv "$WORK/root/kmp/iosApp" "$WORK/root/iosApp"

echo
echo "=== Run with RELATIVE XCODEPROJ_PATH from \$WORK/root/kmp ==="
(
    cd "$WORK/root/kmp"
    XCODEPROJ_PATH='../iosApp/iosApp.xcodeproj' ./gradlew :consumer:integrateLinkagePackage --console=plain
)

echo
echo "=== Where did the synthetic package go? ==="
find "$WORK/root" -type d -name KotlinMultiplatformLinkedPackage -not -path '*/Sources/*'
echo
echo "Expected location (next to the .xcodeproj): $WORK/root/iosApp/KotlinMultiplatformLinkedPackage"
if [ -d "$WORK/root/iosApp/KotlinMultiplatformLinkedPackage" ]; then
    echo "RESULT: not reproduced (synthetic package is in the expected place)"
else
    echo "RESULT: REPRODUCED — synthetic package was created inside the Gradle project dir,"
    echo "while the pbxproj reference (relativePath = KotlinMultiplatformLinkedPackage,"
    echo "relative to the .xcodeproj container) dangles:"
    grep -n 'relativePath' "$WORK/root/iosApp/iosApp.xcodeproj/project.pbxproj" || true
fi

echo
echo "=== Variant: in-tree layout, relative path from repo root ==="
rsync -a --exclude '.git' --exclude '.gradle' --exclude 'build' \
    "$REPO_ROOT/" "$WORK/intree/"
(
    cd "$WORK/intree"
    XCODEPROJ_PATH='iosApp/iosApp.xcodeproj' ./gradlew :consumer:integrateLinkagePackage --console=plain
)
echo "Synthetic package location(s):"
find "$WORK/intree" -type d -name KotlinMultiplatformLinkedPackage -not -path '*/Sources/*'
echo "(expected: \$WORK/intree/iosApp/..., observed on 2.4.0: \$WORK/intree/consumer/iosApp/...)"
