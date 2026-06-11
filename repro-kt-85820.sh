#!/usr/bin/env bash
# Reproduces KT-85820: "Consuming just the package without a product doesn't
# actually enforce versions with lock file alignment"
# https://youtrack.jetbrains.com/issue/KT-85820
#
# Scenario (all local, no network needed):
#   - "TinyDep": a local git Swift package with tags 1.0.0 and 1.1.0
#   - MinimalBridge (this repo, copied to a temp dir): depends on TinyDep
#     with `from: "1.0.0"` in Package.swift (so SwiftPM would pick 1.1.0)
#   - consumer/build.gradle.kts pins TinyDep with
#     `swiftPackage(url = ..., version = exact("1.0.0"), products = listOf())`
#     i.e. the package is consumed WITHOUT any product
#
# Expected: the lock file pins TinyDep at 1.0.0 (the exact() constraint).
# Actual:   .swiftpm-locks/default/swiftImport/Package.resolved pins 1.1.0 —
#           the constraint is ignored because no product of the package is
#           consumed. (The synthetic project under consumer/build/kotlin/
#           swiftImport/ resolves 1.0.0, so the lock file and the actual
#           build even disagree with each other.)
#
# A control run (products = listOf(product("TinyDep"))) shows the lock file
# honoring exact("1.0.0") as soon as a product is consumed.
#
# Everything is generated under a temp dir; local commits/tags are created
# only in that copy, never in this repo. Paths are substituted at runtime, so
# the script works on any machine.
#
# Prereqs: macOS + Xcode, JDK 17, python3. Run from the repo root of a
# regular clone (not a git worktree: SwiftPM cannot clone from a worktree).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
WORK="${KT85820_WORKDIR:-/tmp/kt-85820-repro}"
GIT="git -c user.email=repro@example.com -c user.name=repro"

rm -rf "$WORK"
mkdir -p "$WORK"

### 1. TinyDep: local git package with tags 1.0.0 and 1.1.0 ##################
TINYDEP="$WORK/tinydep"
mkdir -p "$TINYDEP/Sources/TinyDep"
cat > "$TINYDEP/Package.swift" <<'EOF'
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TinyDep",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "TinyDep", targets: ["TinyDep"]),
    ],
    targets: [
        .target(name: "TinyDep"),
    ],
)
EOF
echo 'public enum TinyDep { public static let version = "1.0.0" }' \
    > "$TINYDEP/Sources/TinyDep/TinyDep.swift"
(
    cd "$TINYDEP"
    git init -q
    git add -A && $GIT commit -qm "TinyDep 1.0.0" && git tag 1.0.0
    sed -i '' 's/1\.0\.0/1.1.0/' Sources/TinyDep/TinyDep.swift
    git add -A && $GIT commit -qm "TinyDep 1.1.0" && git tag 1.1.0
)

### 2. Copy of this repo: MinimalBridge depends on TinyDep, tagged v1.1.0 ####
PKG="$WORK/pkg"
git clone -q "$REPO_ROOT" "$PKG"
cat > "$PKG/Package.swift" <<EOF
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MinimalBridge",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "MinimalBridge",
            targets: ["MinimalBridge"],
        ),
    ],
    dependencies: [
        .package(url: "file://$TINYDEP", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "MinimalBridge",
            dependencies: [
                .product(name: "TinyDep", package: "tinydep"),
            ],
        ),
    ],
)
EOF

# PRODUCTS_LINE is swapped between the bug run and the control run.
write_consumer_gradle() { # $1 = products line for the TinyDep swiftPackage
    cat > "$PKG/consumer/build.gradle.kts" <<EOF
@file:OptIn(org.jetbrains.kotlin.gradle.ExperimentalKotlinGradlePluginApi::class)

plugins {
    alias(libs.plugins.kotlinMultiplatform)
}

kotlin {
    compilerOptions {
        optIn.add("kotlinx.cinterop.ExperimentalForeignApi")
    }

    listOf(
        iosArm64(),
        iosSimulatorArm64(),
    ).forEach { target ->
        target.binaries.framework {
            baseName = "Consumer"
            isStatic = true
        }
    }

    swiftPMDependencies {
        iosMinimumDeploymentTarget.set("17.0")
        swiftPackage(
            url = url("file://\${rootProject.projectDir.absolutePath}"),
            version = from("1.1.0"),
            products = listOf(product("MinimalBridge")),
        )
        // KT-85820: exact() constraint on a package consumed without products
        swiftPackage(
            url = url("file://$TINYDEP"),
            version = exact("1.0.0"),
            $1
        )
    }
}
EOF
}

write_consumer_gradle 'products = listOf(),'
(
    cd "$PKG"
    git add -A && $GIT commit -qm "KT-85820: MinimalBridge depends on TinyDep"
    git tag v1.1.0
)

pins() {
    python3 -c "import json,sys; d=json.load(open(sys.argv[1])); \
print(', '.join(f\"{p['identity']}@{p['state']['version']}\" for p in d['pins']))" "$1"
}

run_fetch() {
    (cd "$PKG" && XCODEPROJ_PATH="$PKG/iosApp/iosApp.xcodeproj" \
        ./gradlew -q :consumer:fetchSyntheticImportProjectPackages > /dev/null 2>&1)
}

### 3. Bug run: products = listOf() ##########################################
echo "=== BUG RUN: TinyDep consumed with exact(\"1.0.0\") and products = listOf() ==="
run_fetch
PERSISTED="$PKG/.swiftpm-locks/default/swiftImport/Package.resolved"
SYNTHETIC="$PKG/consumer/build/kotlin/swiftImport/Package.resolved"
echo "persisted lock file (.swiftpm-locks/default/swiftImport/Package.resolved):"
echo "    $(pins "$PERSISTED")"
echo "synthetic project  (consumer/build/kotlin/swiftImport/Package.resolved):"
echo "    $(pins "$SYNTHETIC")"
if pins "$PERSISTED" | grep -q 'tinydep@1\.0\.0'; then
    echo "NOT REPRODUCED: lock file honored exact(\"1.0.0\")."
else
    echo "REPRODUCED: lock file ignored exact(\"1.0.0\") for the product-less package."
fi

### 4. Control run: products = listOf(product("TinyDep")) ####################
echo
echo "=== CONTROL RUN: same, but products = listOf(product(\"TinyDep\")) ==="
write_consumer_gradle 'products = listOf(product("TinyDep")),'
(
    cd "$PKG"
    rm -rf .swiftpm-locks consumer/build/kotlin
    git add -A && $GIT commit -qm "control: consume TinyDep product"
    git tag -f v1.1.0 > /dev/null
)
run_fetch
echo "persisted lock file (.swiftpm-locks/default/swiftImport/Package.resolved):"
echo "    $(pins "$PERSISTED")"
echo "(exact(\"1.0.0\") is honored once a product is consumed.)"
