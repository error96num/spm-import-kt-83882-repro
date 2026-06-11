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
        // KT-85807 repro: consume the repo itself as a *remote* git package via
        // a file:// URL (resolved through the regular SwiftPM fetch/checkout
        // machinery), so that fetchSyntheticImportProjectPackages actually
        // creates a checkout. The path is derived from rootProject.projectDir,
        // so this works on any machine without edits.
        swiftPackage(
            url = url("file://${rootProject.projectDir.absolutePath}"),
            version = from("1.0.0"),
            products = listOf(product("MinimalBridge")),
        )
    }
}
