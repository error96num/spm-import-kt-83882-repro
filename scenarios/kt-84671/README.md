# KT-84671 — relative `XCODEPROJ_PATH` puts the synthetic linkage package in the wrong place

https://youtrack.jetbrains.com/issue/KT-84671

Verified with **Kotlin 2.4.0 (stable)**, Gradle 9.5.1, macOS.

## TL;DR

```bash
./scenarios/kt-84671/reproduce.sh
```

The script builds the layout from the issue in a temp dir:

```
root/iosApp/iosApp.xcodeproj   # Xcode app, OUTSIDE the Gradle project
root/kmp/                      # Gradle project (this repo, minus iosApp/)
```

and runs, from `root/kmp`:

```bash
XCODEPROJ_PATH='../iosApp/iosApp.xcodeproj' ./gradlew :consumer:integrateLinkagePackage
```

## Observed (Kotlin 2.4.0)

- The real Xcode project at `root/iosApp/iosApp.xcodeproj` **is** found and mutated
  (the relative env var is resolved against the Gradle invocation working dir —
  `IntegrateLinkagePackageIntoXcodeProject` uses `gradle.startParameter.currentDir`).
- But the synthetic package is generated at
  `root/kmp/iosApp/KotlinMultiplatformLinkedPackage` — inside the Gradle project —
  because `registerXcodeIntegrationLinkagePackageGeneration` wires
  `syntheticImportProjectRoot` through
  `project.layout.dir { File(envValue).parentFile.resolve(...) }`, which resolves a
  relative `File` against the **subproject directory** (`:consumer`):
  `kmp/consumer/../iosApp` → `kmp/iosApp`.
- The pbxproj gets `relativePath = KotlinMultiplatformLinkedPackage` (sibling of the
  `.xcodeproj`), i.e. `root/iosApp/KotlinMultiplatformLinkedPackage`, which does not
  exist → Xcode fails to resolve the local package.

The same divergence breaks even the plain in-tree layout
(`XCODEPROJ_PATH=iosApp/iosApp.xcodeproj` from the repo root): the synthetic
package lands in `consumer/iosApp/KotlinMultiplatformLinkedPackage`.

Running from the `consumer/` subdirectory with `../../iosApp/iosApp.xcodeproj`
*accidentally* works, because there the working dir equals the subproject dir.
An absolute `XCODEPROJ_PATH` always works.

## Expected

All components of the integration end up under a single root next to the
`.xcodeproj`, regardless of whether `XCODEPROJ_PATH` is relative or absolute —
i.e. both consumers of the env var resolve it against the same base
(the invocation working directory).
