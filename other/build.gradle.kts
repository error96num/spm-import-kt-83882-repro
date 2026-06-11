plugins {
    alias(libs.plugins.kotlinMultiplatform)
}

kotlin {
    iosArm64()
    iosSimulatorArm64()
    // NOTE: no framework, no swiftPMDependencies — this module is NOT the
    // embedAndSign entrypoint used by the Xcode project.
}
