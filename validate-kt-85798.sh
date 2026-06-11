#!/usr/bin/env bash
# Validation scenario for KT-85798:
# "Validate correctness and performance of swift package resolve vs
#  xcodebuild -resolvePackageDependencies with shared checkout directory"
#
# After KT-85617, FetchSyntheticImportProjectPackages relies solely on
# `swift package resolve --scratch-path <checkout>` and a per-identifier shared
# checkout dir (<root>/.swiftpm-locks/<id>/swiftPMCheckout) was introduced.
#
# This script validates two assumptions on stock Kotlin 2.4.0:
#
#  A) Correctness: a checkout populated by `swift package resolve --scratch-path`
#     is consumable by the downstream `xcodebuild build -clonedSourcePackagesDirPath`
#     step (convertSyntheticImportProjectIntoDefFile*) without re-resolution.
#     Expected: PASS (def file generated, workspace-state.json untouched).
#
#  B) Reuse: the shared per-identifier checkout populated by the umbrella fetch
#     task is reused by the per-project fetchSyntheticImportProjectPackages.
#     Observed: FAIL — the per-project fetch task keeps its own scratch dir
#     (consumer/build/kotlin/swiftPMCheckout) and re-resolves + re-checks-out
#     every dependency a second time.
#
# Usage: ./validate-kt-85798.sh
set -euo pipefail
cd "$(dirname "$0")"

# Clean checkout dirs and def-file outputs so both the fetch and the downstream
# xcodebuild step actually execute.
rm -rf .swiftpm-locks consumer/build/kotlin/swiftPMCheckout \
    consumer/build/kotlin/swiftImportDefs consumer/build/kotlin/swiftImportDd
LOG=$(mktemp)

echo "==> Step 1: fetch tasks (umbrella + per-project)"
./gradlew :consumer:fetchSyntheticImportProjectPackages --console=plain -i 2>&1 | tee "$LOG" | grep -E "swift package --scratch-path|Fetched " || true

RESOLVES=$(grep -c "Command: /usr/bin/swift package --scratch-path" "$LOG" || true)
echo
echo "swift package resolve invocations: $RESOLVES"
if [ "$RESOLVES" -ge 2 ]; then
    echo "B) NOT REUSED: dependency resolution + checkout ran ${RESOLVES}x"
    echo "   umbrella scratch dir : .swiftpm-locks/default/swiftPMCheckout"
    echo "   per-project scratch  : consumer/build/kotlin/swiftPMCheckout"
else
    echo "B) REUSED: only one resolve ran (behavior fixed?)"
fi

echo
echo "==> Step 2: downstream xcodebuild step reuses the per-project checkout"
WS=consumer/build/kotlin/swiftPMCheckout/workspace-state.json
CHECKOUT=consumer/build/kotlin/swiftPMCheckout/checkouts/KeychainAccess
cp "$WS" /tmp/kt-85798-ws-before.json
INODE_BEFORE=$(stat -f %i "$CHECKOUT")
REV_BEFORE=$(git -C "$CHECKOUT" rev-parse HEAD)

./gradlew :consumer:convertSyntheticImportProjectIntoDefFileIphonesimulator --console=plain -q >/dev/null

INODE_AFTER=$(stat -f %i "$CHECKOUT")
REV_AFTER=$(git -C "$CHECKOUT" rev-parse HEAD)
if [ "$INODE_BEFORE" = "$INODE_AFTER" ] && [ "$REV_BEFORE" = "$REV_AFTER" ]; then
    echo "A) COMPATIBLE: xcodebuild consumed the swift-resolve checkout without re-cloning the remote dependency"
else
    echo "A) INCOMPATIBLE: xcodebuild re-cloned the remote checkout"
fi
if ! diff -q /tmp/kt-85798-ws-before.json "$WS" >/dev/null; then
    echo "   note: xcodebuild rewrote workspace-state.json (e.g. local-package path re-canonicalization):"
    diff /tmp/kt-85798-ws-before.json "$WS" | head -8 || true
fi
ls consumer/build/kotlin/swiftImportDefs/iphonesimulator/*.def >/dev/null && echo "   def files generated OK"
