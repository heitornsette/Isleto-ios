@preconcurrency import ActivityKit
import Foundation
import Observation
import UIKit
@preconcurrency import UserNotifications

/// Rest between workout sets: a countdown in the workout screen, a Live Activity in the
/// Dynamic Island and a local notification when it ends. Kept in UserDefaults (it belongs
/// to this device and does not sync), so it survives the app being closed.
@MainActor
@Observable
final class RestTimer {
    static let shared = RestTimer()

    private(set) var start: Date?
    private(set) var end: Date?
    private(set) var title = ""

    private static let notificationID = "rest-end"
    private static let defaultsKey = "rest-timer"
    private var finishTask: Task<Void, Never>?
    /// Off for the CI screenshots, where the permission prompt would cover the screen.
    private let notify = !ProcessInfo.processInfo.arguments.contains("--demo-workout")

    var isRunning: Bool { end.map { $0 > .now } ?? false }
    var range: ClosedRange<Date>? {
        guard let start, let end, end > .now else { return nil }
        return start...max(start, end)
    }

    private struct Saved: Codable {
        var start: Date
        var end: Date
        var title: String
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode(Saved.self, from: data), saved.end > .now {
            start = saved.start
            end = saved.end
            title = saved.title
            scheduleFinish()
        } else {
            endActivities()
        }
    }

    /// Starts (or restarts) the rest. `exercise` names it in the Dynamic Island.
    func begin(seconds: Int, exercise: String) {
        guard seconds > 0 else {
            stop()
            return
        }
        let now = Date.now
        start = now
        end = now.addingTimeInterval(TimeInterval(seconds))
        title = "Descanso · \(exercise)"
        changed(restartActivity: true)
    }

    /// Adds (or with a negative value, removes) time. Down to zero, it stops.
    func add(seconds: Int) {
        guard let current = end, current > .now else { return }
        let newEnd = current.addingTimeInterval(TimeInterval(seconds))
        guard newEnd > .now.addingTimeInterval(1) else {
            stop()
            return
        }
        end = newEnd
        changed(restartActivity: false)
    }

    func stop() {
        start = nil
        end = nil
        finishTask?.cancel()
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        endActivities()
    }

    // MARK: System parts

    private func changed(restartActivity: Bool) {
        guard let start, let end else { return }
        if let data = try? JSONEncoder().encode(Saved(start: start, end: end, title: title)) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
        scheduleFinish()
        if notify {
            Task { await scheduleNotification(end: end) }
        }
        if restartActivity {
            startActivity(start: start, end: end)
        } else {
            updateActivity(start: start, end: end)
        }
    }

    /// Clears the state when the rest ends while the app is open, with a tap of haptics.
    private func scheduleFinish() {
        finishTask?.cancel()
        guard let end else { return }
        finishTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            self.start = nil
            self.end = nil
            UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
            self.endActivities()
        }
    }

    private var restActivities: [Activity<TimerActivityAttributes>] {
        Activity<TimerActivityAttributes>.activities.filter { $0.attributes.kind == .rest }
    }

    private func startActivity(start: Date, end: Date) {
        let old = restActivities
        Task {
            for activity in old {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = TimerActivityAttributes.ContentState(start: start, end: end)
        _ = try? Activity.request(
            attributes: TimerActivityAttributes(title: title, kind: .rest),
            content: ActivityContent(state: state, staleDate: end),
            pushType: nil // free Apple ID: no APNs
        )
    }

    /// A local update works without push while the app runs.
    private func updateActivity(start: Date, end: Date) {
        let state = TimerActivityAttributes.ContentState(start: start, end: end)
        let activities = restActivities
        Task {
            for activity in activities {
                await activity.update(ActivityContent(state: state, staleDate: end))
            }
        }
    }

    private func endActivities() {
        let activities = restActivities
        guard !activities.isEmpty else { return }
        Task {
            for activity in activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private func scheduleNotification(end: Date) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        let content = UNMutableNotificationContent()
        content.title = "Descanso acabou"
        content.body = "Hora da próxima série."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)
        try? await center.add(UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: trigger))
    }
}
