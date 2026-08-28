import Foundation
import BackgroundTasks
import os
import UserNotifications
import LanisKit

/// BGAppRefreshTask that re-fetches offline applets and posts a local notification when
/// the substitution plan changed (port of `background_service.dart`, substitutions only for now).
enum BackgroundRefresh {
    static let taskID = "io.github.alessioc42.sph.native.refresh"
    static let logger = os.Logger(subsystem: "io.github.alessioc42.sph.native", category: "bg")

    @MainActor
    static func register(app: AppState) {
        // The launch handler inherits this function's @MainActor isolation, so it must run on
        // the main queue — with `using: nil` the runtime isolation check traps (SIGTRAP).
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: .main) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            let work = Task { @MainActor in
                let changed = await run(app: app)
                task.setTaskCompleted(success: changed != nil)
            }
            task.expirationHandler = { work.cancel() }
        }
        schedule()
    }

    static func schedule(after interval: TimeInterval = 60 * 60) {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        do { try BGTaskScheduler.shared.submit(request); logger.notice("scheduled refresh in \(Int(interval))s") }
        catch { logger.error("schedule failed: \(error.localizedDescription, privacy: .public)") }
    }

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }

    /// Returns the number of substitutions found, nil on failure. Reschedules itself.
    @MainActor
    static func run(app: AppState) async -> Int? {
        defer { schedule() }
        guard let accountID = app.activeAccountID else { return nil }
        if app.session == nil { await app.activate(id: accountID) }
        guard let session = app.session, app.supportedApplets.contains(AppletMeta.substitutions.phpURL) else { return nil }
        do {
            let old = app.snapshots.read(SubstitutionPlan.self, accountID: accountID, applet: .substitutions)?.value
            let plan = try await SubstitutionsParser().fetchHome(session: session)
            try? app.snapshots.write(plan, accountID: accountID, applet: .substitutions)
            let fresh = Set(plan.allSubstitutions.map(\.id)).subtracting(Set(old?.allSubstitutions.map(\.id) ?? []))
            if !fresh.isEmpty { await notify(count: fresh.count) }
            return plan.allSubstitutions.count
        } catch {
            logger.error("refresh failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    static func notify(count: Int) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Neue Vertretungen")
        content.body = String(localized: "\(count) neue Einträge im Vertretungsplan")
        content.sound = .default
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "substitutions", content: content, trigger: nil))
    }
}
