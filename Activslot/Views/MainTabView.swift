import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var homeTodayTapCount = 0
    @State private var calendarTodayTapCount = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                // Smart Plan - The main view for intelligent daily planning
                SmartPlanView()
                    .tabItem {
                        Image(systemName: "brain.head.profile")
                        Text("My Plan")
                    }
                    .tag(0)

                HomeView(resetToTodayTrigger: homeTodayTapCount)
                    .tabItem {
                        Image(systemName: "figure.walk")
                        Text("Activity")
                    }
                    .tag(1)

                ActivslotCalendarView(resetToTodayTrigger: calendarTodayTapCount)
                    .tabItem {
                        Image(systemName: "calendar")
                        Text("Calendar")
                    }
                    .tag(2)

                SettingsView()
                    .tabItem {
                        Image(systemName: "gearshape.fill")
                        Text("Settings")
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
