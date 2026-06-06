# Minimal repro for [KT-83882](https://youtrack.jetbrains.com/issue/KT-83882)

> "Search for a way to reproduce 'Missing package product' in KMP IDE plugin"

Deterministic minimal reproduction of the **`XCSwiftPackageProductDependency` missing
`package = <UUID>` linkage** bug in Kotlin Multiplatform's SwiftPM Import.

Also exhibits the symptom of [KT-83876](https://youtrack.jetbrains.com/issue/KT-83876)
("Improve idempotency checks for integrateLinkagePackage") on re-runs.

## TL;DR

```bash
XCODEPROJ_PATH="$PWD/iosApp/iosApp.xcodeproj" ./gradlew :consumer:integrateLinkagePackage
awk '/Begin XCSwiftPackageProductDependency section/,/End XCSwiftPackageProductDependency section/' \
    iosApp/iosApp.xcodeproj/project.pbxproj
```

Expected: `XCSwiftPackageProductDependency` entry contains a `package = <UUID>;`
field linking back to the `XCLocalSwiftPackageReference` defined elsewhere in the
same pbxproj.

Actual: that line is omitted entirely. Opening the project in Xcode produces
`Missing package product 'KotlinMultiplatformLinkedPackage'`.

## Environment

| Tool | Version |
|---|---|
| Kotlin | 2.4.0 (stable) — default in this repo |
| Gradle | 9.5.1 |
| JDK | 17 |
| Xcode | with iPhoneOS26.2 SDK |
| macOS | (host) |

## Project structure

```
.
├── Package.swift                              # trivial SPM, one product "MinimalBridge"
├── Sources/MinimalBridge/MinimalBridge.swift  # @objc class with one static method
├── consumer/
│   ├── build.gradle.kts                       # kotlinMultiplatform + swiftPMDependencies
│   └── src/commonMain/kotlin/Placeholder.kt   # placeholder source
├── iosApp/
│   ├── iosApp.xcodeproj/project.pbxproj       # Xcode project that integrateLinkagePackage mutates
│   └── iosApp/                                # SwiftUI app shell
├── build.gradle.kts
├── settings.gradle.kts                        # single module :consumer
├── gradle/libs.versions.toml                  # Kotlin version pin
└── README.md (this file)
```

## How the broken state looks

After running `integrateLinkagePackage`, the pbxproj contains:

```
/* Begin XCLocalSwiftPackageReference section */
        <UUID-A> = {
            isa = XCLocalSwiftPackageReference;
            relativePath = KotlinMultiplatformLinkedPackage;
        };
/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
        <UUID-B> = {
            isa = XCSwiftPackageProductDependency;
            //  ^^^^ EXPECTED: package = <UUID-A>;
            //  ^^^^ ACTUAL: line is missing entirely
            productName = KotlinMultiplatformLinkedPackage;
        };
/* End XCSwiftPackageProductDependency section */
```

(UUIDs are randomly generated per run; the structural bug is identical.)

## Idempotency check (KT-83876)

A 2nd run of `integrateLinkagePackage` reports:

```
> Task :consumer:integrateLinkagePackage
Product already referenced, nothing to do
```

…while the pbxproj remains in the broken state. The idempotency check sees a
match by `productName` but does not detect that the `package` link is missing.

## Scope: localSwiftPackage vs swiftPackage(url=...)

The bug is **independent of the user-facing DSL form**:

- `localSwiftPackage(directory = ...)` — verified ✅ reproduces (default in this repo)
- `swiftPackage(url = ..., version = ...)` — verified ✅ reproduces (see swap recipe below)

This is because the Kotlin Gradle Plugin always inserts a "synthetic linkage package"
into `iosApp/KotlinMultiplatformLinkedPackage/` and references it as
`XCLocalSwiftPackageReference` regardless of the user-facing DSL choice. The
generated pbxproj structure is identical in both cases.

### Swap to swiftPackage(url=...) variant

Replace `localSwiftPackage(...)` in `consumer/build.gradle.kts` with:

```kotlin
swiftPackage(
    url = url("file://${rootProject.projectDir.absolutePath}"),
    version = from("1.0.0"),
    products = listOf(product("MinimalBridge")),
)
```

(The repo is tagged `v1.0.0` for this purpose. Replace the URL with a remote git
URL if you prefer.)

Reset pbxproj to baseline (`git checkout v1.0.0 -- iosApp/iosApp.xcodeproj/project.pbxproj`)
and re-run `integrateLinkagePackage`. Same broken output.

## Workaround

Manually add the missing line to `XCSwiftPackageProductDependency`, where
`<UUID-A>` is the existing `XCLocalSwiftPackageReference`'s UUID in the same file:

```diff
 <UUID-B> = {
     isa = XCSwiftPackageProductDependency;
+    package = <UUID-A>;
     productName = KotlinMultiplatformLinkedPackage;
 };
```

Then in Xcode: File → Packages → Reset Package Caches → Clean Build Folder → Run.

## Reset to baseline (after running the task)

`integrateLinkagePackage` mutates `iosApp/iosApp.xcodeproj/project.pbxproj` and creates `iosApp/KotlinMultiplatformLinkedPackage/`. To reset:

```bash
git checkout v1.0.0 -- iosApp/iosApp.xcodeproj/project.pbxproj
rm -rf iosApp/KotlinMultiplatformLinkedPackage
```

## License

Apache License 2.0. See [LICENSE](./LICENSE).
