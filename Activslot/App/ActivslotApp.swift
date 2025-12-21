import SwiftUI

@main
struct ActivslotApp: App {
    @StateObject private var healthKitManager = HealthKitManager.shared
    @StateObject private var calendarManager = CalendarManager.shared
    @StateObject private var userPreferences = UserPreferences.shared
    @StateObject private var outlookManager = OutlookManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(healthKitManager)
                .environmentObject(calendarManager)
                .environmentObject(userPreferences)
                .environmentObject(outlookManager)
        }
    }
}
