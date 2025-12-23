import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var homeTodayTapCount = 0
    @State private var calendarTodayTapCount = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                HomeView(resetToTodayTrigger: homeTodayTapCount)
                    .tabItem {
                        Image(systemName: "house.fill")
                        Text("Today")
                    }
                    .tag(0)

                ActivslotCalendarView(resetToTodayTrigger: calendarTodayTapCount)
                    .tabItem {
                        Image(systemName: "calendar")
                        Text("Calendar")
                    }
                    .tag(1)

                SettingsView()
                    .tabItem {
                        Image(systemName: "gearshape.fill")
                        Text("Settings")
                    }
                    .tag(2)
            }
            .tint(.blue)

            // Invisible button overlays on tabs to detect re-tap
            GeometryReader { geometry in
                let tabWidth = geometry.size.width / 3

                // Today tab overlay
                Color.clear
                    .frame(width: tabWidth, height: 49)
                    .contentShape(Rectangle())
                    .position(x: tabWidth / 2, y: geometry.size.height - 24.5)
                    .onTapGesture {
                        if selectedTab == 0 {
                            homeTodayTapCount += 1
                        } else {
                            selectedTab = 0
                        }
                    }

                // Calendar tab overlay
                Color.clear
                    .frame(width: tabWidth, height: 49)
                    .contentShape(Rectangle())
                    .position(x: tabWidth * 1.5, y: geometry.size.height - 24.5)
                    .onTapGesture {
                        if selectedTab == 1 {
                            calendarTodayTapCount += 1
                        } else {
                            selectedTab = 1
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
