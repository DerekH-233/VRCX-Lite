import UIKit

// MARK: - Haptic Feedback Manager

/// Lightweight wrapper around UIKit haptic engines.
/// Invoke from any context (main-thread only for UI-impact generators).
enum HapticManager {

    /// Light tap — row selection, button press.
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Medium tap — confirmation actions (accept invite, send request).
    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Heavy thud — destructive actions (logout, unfriend).
    static func heavy() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    /// Success notification — login success, invite accepted.
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Warning notification — 2FA required, rate-limit hit.
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// Error notification — auth failure, network error.
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    /// Light selection change — segment/tab switches.
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
