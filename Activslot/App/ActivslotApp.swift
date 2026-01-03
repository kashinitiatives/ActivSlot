import SwiftUI
import UserNotifications

@main
struct ActivslotApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var healthKitManager = HealthKitManager.shared
    @StateObject private var calendarManager = CalendarManager.shared
    @StateObject private var userPreferences = UserPreferences.shared
    @StateObject private var outlookManager = OutlookManager.shared
    @StateObject private var notificationManager = NotificationManager.shared

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(healthKitManager)
                .environmentObject(calendarManager)
                .environmentObject(userPreferences)
                .environmentObject(outlookManager)
                .environmentObject(notificationManager)
                .onChange(of: scenePhase) { _, newPhase in
                    handleScenePhaseChange(newPhase)
                }
                #if DEBUG
                .task {
                    await runDebugTestScenarioIfRequested()
                }
                #endif
        }
    }

    #if DEBUG
    /// Runs a test scenario based on launch argument or environment variable
    /// Usage: Set TEST_SCENARIO environment variable to one of:
    /// - "busy_executive", "light_day", "almost_goal", "goal_reached", "walkable_meetings", "full_test"
    private func runDebugTestScenarioIfRequested() async {
        // Check for test scenario from environment variable
        guard let scenario = ProcessInfo.processInfo.environment["TEST_SCENARIO"] else {
            return
        }

        print("DEBUG: Running test scenario: \(scenario)")

        let testManager = TestDataManager.shared

        switch scenario.lowercased() {
        case "busy_executive":
            await testManager.setupBusyExecutiveScenario()
        case "light_day":
            await testManager.setupLightDayScenario()
        case "almost_goal":
            await testManager.setupAlmostThereScenario()
        case "goal_reached":
            await testManager.setupGoalReachedScenario()
        case "walkable_meetings":
            await testManager.setupWalkableMeetingsScenario()
        case "full_test":
            await testManager.generateFullTestScenario()
        case "clear":
            await testManager.clearAllTestData()
        case "production_tests":
            // Production tests - run from TestDataManager
            print("Production tests available in TestDataManager")
        default:
            print("DEBUG: Unknown test scenario: \(scenario)")
        }

        print("DEBUG: Test scenario '\(scenario)' completed")
    }
    #endif

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            // App became active - refresh notification authorization status
            NotificationManager.shared.checkAuthorizationStatus()

            // Refresh calendar data and regenerate plans
            Task {
                // Refresh calendar events first
                await calendarManager.refreshEvents()

                // Regenerate movement plans with updated calendar data
                await MovementPlanManager.shared.generatePlans()

                // Morning refresh for smart daily planning (6-10 AM window)
                let hour = Calendar.current.component(.hour, from: Date())
                if hour >= 6 && hour < 10 {
                    await DailyPlanSyncCoordinator.shared.refreshTodayPlan()
                }

                // Refresh daily notifications and autopilot scheduling
                await NotificationManager.shared.refreshDailyNotifications()
                await AutopilotManager.shared.scheduleWalksForTomorrow()
            }

        case .background:
            // App went to background - good time to schedule notifications and autopilot walks
            Task {
                await NotificationManager.shared.refreshDailyNotifications()
                await AutopilotManager.shared.scheduleWalksForTomorrow()

                // Evening sync for tomorrow's plan (if past sync time)
                let hour = Calendar.current.component(.hour, from: Date())
                let prefs = UserPreferences.shared
                if hour >= prefs.smartPlanSyncTimeHour {
                    await DailyPlanSyncCoordinator.shared.syncTomorrowPlan()
                }

                // Cleanup old managed events
                DailyPlanSyncCoordinator.shared.cleanupOldManagedEvents()
            }

        case .inactive:
            break

        @unknown default:
            break
        }
    }
}

// MARK: - App Delegate for Notification Handling

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Set notification delegate
        UNUserNotificationCenter.current().delegate = self

        // Register notification categories (for action buttons)
        NotificationManager.shared.registerNotificationCategories()

        return true
    }

    // Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification banner even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    // Handle notification action (user tapped on notification or action button)
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let actionIdentifier = response.actionIdentifier

        // Handle different notification types
        if let notificationType = userInfo["type"] as? String {
            switch notificationType {
            case "eveningBriefing":
                handleEveningBriefingAction(actionIdentifier, userInfo: userInfo)

            case "walkableMeeting":
                handleWalkableMeetingAction(actionIdentifier, userInfo: userInfo)

            case "workoutReminder":
                handleWorkoutReminderAction(actionIdentifier, userInfo: userInfo)

            default:
                break
            }
        }

        completionHandler()
    }

    private func handleEveningBriefingAction(_ action: String, userInfo: [AnyHashable: Any]) {
        switch action {
        case "PLAN_DAY", UNNotificationDefaultActionIdentifier:
            // User wants to plan - app opens to home view automatically
            // Could post a notification to navigate to a specific view if needed
            NotificationCenter.default.post(name: .openDayPlan, object: nil, userInfo: userInfo)

        case "DISMISS":
            break

        default:
            break
        }
    }

    private func handleWalkableMeetingAction(_ action: String, userInfo: [AnyHashable: Any]) {
        switch action {
        case "START_WALKING", UNNotificationDefaultActionIdentifier:
            // User wants to start walking - could start a walk tracking session
            NotificationCenter.default.post(name: .startWalkSession, object: nil, userInfo: userInfo)

        case "SKIP":
            break

        default:
            break
        }
    }

    private func handleWorkoutReminderAction(_ action: String, userInfo: [AnyHashable: Any]) {
        switch action {
        case "START_WORKOUT", UNNotificationDefaultActionIdentifier:
            // User wants to start workout
            NotificationCenter.default.post(name: .startWorkoutSession, object: nil, userInfo: userInfo)

        case "SNOOZE":
            // Schedule another reminder in 15 minutes
            let snoozeTime = Date().addingTimeInterval(15 * 60)
            NotificationManager.shared.scheduleWorkoutReminder(at: snoozeTime, message: "Snoozed reminder - time to workout!")

        default:
            break
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let openDayPlan = Notification.Name("openDayPlan")
    static let startWalkSession = Notification.Name("startWalkSession")
    static let startWorkoutSession = Notification.Name("startWorkoutSession")
}
