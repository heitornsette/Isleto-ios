@preconcurrency import ActivityKit
import Foundation
import IsletoCore
import Observation
@preconcurrency import UserNotifications
import WidgetKit

/// State of the "Hoje" screen. The rules live in IsletoCore; this calls them,
/// keeps what the screen shows, and drives the system parts (Live Activity,
/// notifications, widget reloads).
@MainActor
@Observable
final class TodayModel {
    private(set) var status: SharedContainer.Status = .missingGroupID
    private(set) var summary: DaySummary?
    private(set) var errorText: String?
    private(set) var schemaVersion: Int?
    private(set) var appProfile: ProvisioningProfile?
    private(set) var widgetProfile: ProvisioningProfile?
    private(set) var focusMessage: String?

    private static let notificationID = "focus-end"
    private var settleTask: Task<Void, Never>?

    var activitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
    var runningActivities: Int { Activity<TimerActivityAttributes>.activities.count }

    // MARK: Loading

    func reload() {
        status = SharedData.status()
        appProfile = ProvisioningProfile.load(bundleURL: Bundle.main.bundleURL)
        widgetProfile = Bundle.main.builtInPlugInsURL.flatMap {
            ProvisioningProfile.load(bundleURL: $0.appending(path: "IsletoWidgets.appex"))
        }
        do {
            let store = try SharedData.store()
            summary = try store.today()
            schemaVersion = try store.schemaVersion()
            errorText = nil
        } catch {
            summary = nil
            schemaVersion = nil
            errorText = error.localizedDescription
        }
        syncFocusSideEffects()
    }

    /// Runs a change, then reloads the screen and the widget.
    private func change(_ work: (IsletoStore) throws -> Void) {
        do {
            try work(SharedData.store())
        } catch {
            errorText = error.localizedDescription
        }
        reload()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Water

    func addWater() { change { try $0.water.add() } }
    func undoWater() { change { _ = try $0.water.undoLast() } }

    // MARK: Focus

    /// - Parameter notify: false only for CI screenshots, where the permission
    ///   prompt would cover the screen.
    func startFocus(notify: Bool = true) {
        var started: ActiveFocus?
        change { started = try $0.focus.start() }
        guard let session = started else { return }
        startActivity(for: session)
        if notify {
            Task { await self.scheduleNotification(for: session) }
        }
    }

    func cancelFocus() {
        change { try $0.focus.cancel() }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        focusMessage = "Foco cancelado."
    }

    /// Keeps the Live Activity and the end-of-session reload in step with the database.
    private func syncFocusSideEffects() {
        settleTask?.cancel()
        guard let active = summary?.activeFocus else {
            endActivities()
            return
        }
        // Reload when the session ends, so it is saved and counted while the app is open.
        let delay = max(0, active.end.timeIntervalSinceNow) + 0.5
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.focusMessage = "Foco concluído."
            self?.reload()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func startActivity(for session: ActiveFocus) {
        guard activitiesEnabled else {
            focusMessage = "Live Activities desativadas para o Isleto em Ajustes."
            return
        }
        guard Activity<TimerActivityAttributes>.activities.isEmpty else { return }
        let state = TimerActivityAttributes.ContentState(start: session.start, end: session.end)
        do {
            _ = try Activity.request(
                attributes: TimerActivityAttributes(title: "Foco"),
                content: ActivityContent(state: state, staleDate: session.end),
                pushType: nil // free Apple ID: no APNs
            )
            focusMessage = nil
        } catch {
            focusMessage = "Live Activity não iniciou: \(error.localizedDescription)"
        }
    }

    private func endActivities() {
        let activities = Activity<TimerActivityAttributes>.activities
        guard !activities.isEmpty else { return }
        Task {
            for activity in activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// Local notification at the end of the session. Works on a free Apple ID:
    /// only remote (push) notifications need a paid account.
    private func scheduleNotification(for session: ActiveFocus) async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        let content = UNMutableNotificationContent()
        content.title = "Foco concluído"
        content.body = "\(session.minutes) min de foco. Hora de uma pausa."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, session.end.timeIntervalSinceNow), repeats: false)
        try? await center.add(UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: trigger))
    }

    // MARK: Diagnostics

    /// Text the user copies into a bug report. No personal data: only identifiers
    /// of this app, versions and statuses.
    func diagnostics() -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let statusText: String = switch status {
        case .ready(let id, _): "OK (\(id))"
        case .missingGroupID: "SEM ID NO INFO.PLIST"
        case .unavailable(let id): "INDISPONÍVEL (\(id))"
        }
        let today = summary.map {
            "água \($0.waterMl)/\($0.waterGoalMl) ml, \($0.focusSessions) foco(s), \($0.habits.count) hábito(s)"
        } ?? "—"
        return """
        Isleto \(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))
        Commit: \(info["IsletoCommit"] as? String ?? "?")
        Bundle ID: \(Bundle.main.bundleIdentifier ?? "?")
        iOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        App Group: \(statusText)
        Grupos concedidos (app): \(Self.describe(appProfile))
        Grupos concedidos (widget): \(Self.describe(widgetProfile))
        Perfil expira: \(appProfile?.expirationDate?.formatted(date: .abbreviated, time: .shortened) ?? "?")
        Banco: \(schemaVersion.map { "esquema v\($0)" } ?? "não abriu")
        Hoje: \(today)
        Foco ativo: \(summary?.activeFocus.map { "até \($0.end.formatted(date: .omitted, time: .shortened))" } ?? "não")
        Erro: \(errorText ?? "nenhum")
        Live Activities: \(activitiesEnabled ? "permitidas" : "bloqueadas"), \(runningActivities) ativa(s)
        """
    }

    static func describe(_ profile: ProvisioningProfile?) -> String {
        guard let profile else { return "sem perfil embutido" }
        return profile.appGroups.isEmpty ? "nenhum" : profile.appGroups.joined(separator: ", ")
    }

    // MARK: CI screenshots

    /// Launch arguments used only by the CI screenshot script.
    func runDemo(arguments: [String]) {
        if arguments.contains("--demo-focus") {
            startFocus(notify: false)
        }
    }
}
