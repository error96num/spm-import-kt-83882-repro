import Foundation

/// Minimal @objc bridge for KMP SPM Import repro.
@objc public final class MinimalBridge: NSObject {
    @objc public static func hello() -> String {
        return "Hello from MinimalBridge"
    }
}
