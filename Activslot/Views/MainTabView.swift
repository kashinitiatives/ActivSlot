import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: Int
    @State private var homeTodayTapCount = 0
    @State private var calendarTodayTapCount = 0

    init() {
        #if DEBUG
        // Allow starting on specific tab via environment variable (0=MyPlan, 1=Activity, 2=Calendar, 3=Settings)
        if let tabStr = ProcessInfo.processInfo.environment["START_TAB"],
           let tab = Int(tabStr) {
            _selectedTab = State(initialValue: tab)
        } else {
            _selectedTab = State(initialValue: 0)
        }
        #else
        _selectedTab = State(initialValue: 0)
        #endif
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                // Smart Plan - The main view for intelligent daily planning
                SmartPlanView()
                    .tabItem {
                        Label("My Plan", systemImage: "list.bullet.clipboard")
                    }
                    .tag(0)

                HomeView(resetToTodayTrigger: homeTodayTapCount)
                    .tabItem {
                        Label("Activity", systemImage: "figure.walk")
                    }
                    .tag(1)

                ActivslotCalendarView(resetToTodayTrigger: calendarTodayTapCount)
                    .tabItem {
                        Label("Calendar", systemImage: "calendar")
                    }
                    .tag(2)

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                    .tag(3)
            }
            .tint(.green)

            // Invisible button overlays on tabs to detect re-tap
            GeometryReader { geometry in
                let tabWidth = geometry.size.width / 4

                // Activity tab overlay (was Today, now index 1)
                Color.clear
                    .frame(width: tabWidth, height: 49)
                    .contentShape(Rectangle())
                    .position(x: tabWidth * 1.5, y: geometry.size.height - 24.5)
                    .onTapGesture {
                        if selectedTab == 1 {
                            homeTodayTapCount += 1
                        } else {
                            selectedTab = 1
                        }
                    }

                // Calendar tab overlay (now index 2)
                Color.clear
                    .frame(width: tabWidth, height: 49)
                    .contentShape(Rectangle())
                    .position(x: tabWidth * 2.5, y: geometry.size.height - 24.5)
                    .onTapGesture {
                        if selectedTab == 2 {
                            calendarTodayTapCount += 1
                        } else {
                            selectedTab = 2
                        }
                    }
            }
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(HealthKitManager.shared)
        .environmentObject(UserPreferences.shared)
        .environmentObject(CalendarManager.shared)
}
