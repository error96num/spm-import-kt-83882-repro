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
        localSwiftPackage(
            directory = rootProject.layout.projectDirectory,
            products = listOf("MinimalBridge"),
        )
    }
}
