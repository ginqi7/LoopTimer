import Foundation

extension Notification.Name {
    /// Posted by `StopTimerIntent` (which runs in the app process) to ask the
    /// store to stop the running session.
    static let stopTimerIntent = Notification.Name("stopTimerIntent")
}
