#!/usr/bin/env bash
# Reproduces KT-85807: "Fetch task is not invalidated if checkout is removed"
# https://youtrack.jetbrains.com/issue/KT-85807
#
# On this branch, consumer/build.gradle.kts consumes this repo itself as a
# remote git package via `swiftPackage(url = url("file://<repo root>"),
# version = from("1.0.0"))`. The file:// URL is derived from
# rootProject.projectDir, so no path edits are needed; no network access is
# required either (the repo is tagged v1.0.0).
#
# Prereqs: macOS + Xcode, JDK 17. Run from the repo root of a regular clone
# (not a git worktree: SwiftPM cannot clone from a worktree directory).
set -euo pipefail
cd "$(dirname "$0")"

CHECKOUTS="consumer/build/kotlin/swiftPMCheckout/checkouts"

echo "=== 1st run: fetch task executes and creates the checkout ==="
XCODEPROJ_PATH="$PWD/iosApp/iosApp.xcodeproj" \
    ./gradlew :consumer:fetchSyntheticImportProjectPackages
echo "--- checkout contents:"
ls "$CHECKOUTS"

echo
echo "=== removing the checkout: rm -rf $CHECKOUTS ==="
rm -rf "$CHECKOUTS"

echo
echo "=== 2nd run: fetch task should re-execute, but reports UP-TO-DATE ==="
XCODEPROJ_PATH="$PWD/iosApp/iosApp.xcodeproj" \
    ./gradlew :consumer:fetchSyntheticImportProjectPackages

echo
if [ -d "$CHECKOUTS" ]; then
    echo "NOT REPRODUCED: the checkout was recreated."
else
    echo "REPRODUCED: :consumer:fetchSyntheticImportProjectPackages was" \
         "UP-TO-DATE and the checkout was NOT recreated."
    echo "(workspace-state.json under consumer/build/kotlin/swiftPMCheckout/" \
         "still points at the now-missing checkout.)"
fi
