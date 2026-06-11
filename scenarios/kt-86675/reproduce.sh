#!/usr/bin/env bash
#
# Reproduces the failure mode behind KT-86675: integrateLinkagePackage is
# registered on every KMP subproject, so it can be invoked on a module that is
# NOT the embedAndSign entrypoint (here `:other`, which has native targets but
# no swiftPMDependencies and no framework). The invocation succeeds silently:
# the synthetic package generation task is SKIPPED (onlyIf is false), but the
# integrate task still mutates the Xcode project, leaving a dangling
# XCLocalSwiftPackageReference. The Xcode project then fails to resolve.
#
# https://youtrack.jetbrains.com/issue/KT-86675
#
# Usage: ./scenarios/kt-86675/reproduce.sh
# (run from the repo root; requires macOS + Xcode; mutates iosApp/ in-place,
# restore with: git checkout -- iosApp/iosApp.xcodeproj/project.pbxproj
#               && rm -rf iosApp/KotlinMultiplatformLinkedPackage)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

echo "=== Invoke integrateLinkagePackage on the WRONG module (:other) ==="
XCODEPROJ_PATH="$PWD/iosApp/iosApp.xcodeproj" ./gradlew :other:integrateLinkagePackage --console=plain

echo
echo "=== Result ==="
echo "pbxproj package references:"
grep -n 'relativePath = KotlinMultiplatformLinkedPackage\|productName = KotlinMultiplatformLinkedPackage' \
    iosApp/iosApp.xcodeproj/project.pbxproj || true
if [ -d iosApp/KotlinMultiplatformLinkedPackage ]; then
    echo "Synthetic package dir exists."
else
    echo "Synthetic package dir was NOT generated (generation task was SKIPPED for :other)"
    echo "=> the pbxproj reference dangles. Xcode package resolution fails:"
    (
        cd iosApp
        xcodebuild -resolvePackageDependencies -project iosApp.xcodeproj -scheme iosApp 2>&1 \
            | grep -E 'cannot be accessed|Could not resolve' || true
    )
fi
