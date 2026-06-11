# KT-86675 — `integrateLinkagePackage` on the wrong subproject silently corrupts the Xcode project

https://youtrack.jetbrains.com/issue/KT-86675

Verified with **Kotlin 2.4.0 (stable)**, Gradle 9.5.1, macOS.

## Setup

This branch adds a second KMP module `:other` next to `:consumer`:

- `:consumer` — declares the framework and `swiftPMDependencies { localSwiftPackage(...) }`;
  this is the module the Xcode project's embedAndSign phase is meant to use.
- `:other` — has iOS native targets but **no** `swiftPMDependencies` and **no** framework.

Because `SwiftImportSetupAction` is a `KotlinProjectSetupAction`,
`integrateLinkagePackage` / `integrateEmbedAndSign` are registered on **both**
modules; nothing validates which module the Xcode project actually uses.

## Reproduce

```bash
./scenarios/kt-86675/reproduce.sh
```

i.e., from a clean `iosApp/`:

```bash
XCODEPROJ_PATH="$PWD/iosApp/iosApp.xcodeproj" ./gradlew :other:integrateLinkagePackage
```

## Observed (Kotlin 2.4.0)

- `:other:generateSyntheticLinkageSwiftPMImportProjectForLinkageForCli` is
  **SKIPPED** (`onlyIf` is false — no SwiftPM dependencies), so no synthetic
  package directory is generated anywhere.
- `:other:integrateLinkagePackage` still runs and **mutates the pbxproj**, adding
  `XCLocalSwiftPackageReference (relativePath = KotlinMultiplatformLinkedPackage)`
  and an `XCSwiftPackageProductDependency`.
- BUILD SUCCESSFUL, no warning. But the reference dangles; Xcode fails with:

  ```
  xcodebuild: error: Could not resolve package dependencies:
    the package at '.../iosApp/KotlinMultiplatformLinkedPackage' cannot be accessed
    ("The folder "KotlinMultiplatformLinkedPackage" doesn't exist.")
  ```

- An unqualified `./gradlew integrateLinkagePackage` runs the task on **all**
  modules against the same pbxproj (`:consumer` then `:other` here); the end
  state only happens to be consistent because `:consumer` ran too.

## Expected

Calling `integrateLinkagePackage` on a module that is not the embedAndSign
entrypoint (or on more than one module) should fail or warn with an actionable
message instead of silently writing a dangling package reference into the
Xcode project.

## Cleanup

```bash
git checkout -- iosApp/iosApp.xcodeproj/project.pbxproj
rm -rf iosApp/KotlinMultiplatformLinkedPackage
```
