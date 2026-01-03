import Foundation
import MSAL
import SwiftUI

// MARK: - Outlook Calendar Event

struct OutlookEvent: Identifiable, Codable {
    let id: String
    let subject: String
    let startDateTime: Date
    let endDateTime: Date
    let isAllDay: Bool
    let isOnlineMeeting: Bool
    let attendeesCount: Int
    let organizerEmail: String?
    let location: String?

    var duration: Int {
        Int(endDateTime.timeIntervalSince(startDateTime) / 60)
    }

    // Convert to CalendarEvent for unified handling
    func toCalendarEvent() -> CalendarEvent {
        CalendarEvent(
            id: id,
            title: subject,
            startDate: startDateTime,
            endDate: endDateTime,
            attendeeCount: attendeesCount,
            isOrganizer: false,
            location: location
        )
    }
}

// MARK: - Graph API Response Models

struct GraphCalendarResponse: Codable {
    let value: [GraphEvent]
}

struct GraphEvent: Codable {
    let id: String
    let subject: String?
    let start: GraphDateTime
    let end: GraphDateTime
    let isAllDay: Bool?
    let isOnlineMeeting: Bool?
    let attendees: [GraphAttendee]?
    let organizer: GraphOrganizer?
    let location: GraphLocation?
}

struct GraphDateTime: Codable {
    let dateTime: String
    let timeZone: String
}

struct GraphAttendee: Codable {
    let emailAddress: GraphEmailAddress
    let status: GraphResponseStatus?
}

struct GraphEmailAddress: Codable {
    let address: String?
    let name: String?
}

struct GraphResponseStatus: Codable {
    let response: String?
}

struct GraphOrganizer: Codable {
    let emailAddress: GraphEmailAddress
}

struct GraphLocation: Codable {
    let displayName: String?
}

// MARK: - Outlook Manager

class OutlookManager: ObservableObject {
    static let shared = OutlookManager()

    // Azure App Client ID - registered in Azure Portal
    private let clientId = "a658536a-394e-455e-814b-3ca249914d14"

    // Redirect URI - must match exactly what's in Azure Portal
    private let redirectUri = "msala658536a-394e-455e-814b-3ca249914d14://auth"

    // Scopes needed for calendar read access
    private let scopes = ["Calendars.Read", "User.Read"]

    private var applicationContext: MSALPublicClientApplication?
    private var webViewParameters: MSALWebviewParameters?

    @Published var isSignedIn = false
    @Published var userEmail: String?
    @Published var userName: String?
    @Published var outlookEvents: [OutlookEvent] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private init() {
        setupMSAL()
        checkExistingAccount()
    }

    // MARK: - MSAL Setup

    private func setupMSAL() {
        guard !clientId.isEmpty else {
            #if DEBUG
            print("OutlookManager: Client ID not configured")
            #endif
            return
        }

        do {
            let config = MSALPublicClientApplicationConfig(clientId: clientId)

            // Set redirect URI explicitly to match Azure Portal
            config.redirectUri = redirectUri

            // Allow any organizational directory (multi-tenant)
            guard let authorityURL = URL(string: "https://login.microsoftonline.com/common") else {
                errorMessage = "Failed to initialize Microsoft authentication"
                return
            }
            config.authority = try MSALAADAuthority(url: authorityURL)

            applicationContext = try MSALPublicClientApplication(configuration: config)

            #if DEBUG
            print("OutlookManager: MSAL initialized with redirect URI: \(redirectUri)")
            #endif
        } catch {
            #if DEBUG
            print("Failed to create MSAL application: \(error)")
            #endif
            errorMessage = "Failed to initialize Microsoft authentication"
        }
    }

    private func checkExistingAccount() {
        guard let application = applicationContext else { return }

        do {
            let accounts = try application.allAccounts()
            if let account = accounts.first {
                isSignedIn = true
                userEmail = account.username
                userName = account.username?.components(separatedBy: "@").first
            }
        } catch {
            #if DEBUG
            print("Error checking existing accounts: \(error)")
            #endif
        }
    }

    // MARK: - Sign In

    @MainActor
    func signIn(from viewController: UIViewController? = nil) async throws {
        guard let application = applicationContext else {
            throw OutlookError.notConfigured
        }

        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        // Get the presenting view controller
        guard let presentingVC = viewController ?? getRootViewController() else {
            throw OutlookError.noViewController
        }

        let webViewParams = MSALWebviewParameters(authPresentationViewController: presentingVC)
        let interactiveParams = MSALInteractiveTokenParameters(scopes: scopes, webviewParameters: webViewParams)

        do {
            let result = try await application.acquireToken(with: interactiveParams)

            await MainActor.run {
                self.isSignedIn = true
                self.userEmail = result.account.username
                self.userName = result.account.username?.components(separatedBy: "@").first
            }

            // Fetch calendar events after successful sign in
            try await fetchTodayEvents()

        } catch let error as NSError {
            if error.domain == MSALErrorDomain {
                if error.code == MSALError.userCanceled.rawValue {
                    throw OutlookError.userCancelled
                }
            }
            throw OutlookError.authFailed(error.localizedDescription)
        }
    }

    // MARK: - Sign Out

    @MainActor
    func signOut() async {
        guard let application = applicationContext else { return }

        do {
            let accounts = try application.allAccounts()
            for account in accounts {
                try application.remove(account)
            }

            isSignedIn = false
            userEmail = nil
            userName = nil
            outlookEvents = []

        } catch {
            #if DEBUG
            print("Error signing out: \(error)")
            #endif
        }
    }

    // MARK: - Token Acquisition

    private func getAccessToken() async throws -> String {
        guard let application = applicationContext else {
            throw OutlookError.notConfigured
        }

        let accounts = try application.allAccounts()
        guard let account = accounts.first else {
            throw OutlookError.notSignedIn
        }

        let silentParams = MSALSilentTokenParameters(scopes: scopes, account: account)

        do {
            let result = try await application.acquireTokenSilent(with: silentParams)
            return result.accessToken
        } catch {
            // Silent token acquisition failed, need interactive sign-in
            throw OutlookError.tokenExpired
        }
    }

    // MARK: - Fetch Events

    func fetchEvents(for date: Date) async throws -> [OutlookEvent] {
        let accessToken = try await getAccessToken()

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        let startStr = dateFormatter.string(from: startOfDay)
        let endStr = dateFormatter.string(from: endOfDay)

        let urlString = "https://graph.microsoft.com/v1.0/me/calendarview?startDateTime=\(startStr)&endDateTime=\(endStr)&$select=id,subject,start,end,isAllDay,isOnlineMeeting,attendees,organizer,location&$orderby=start/dateTime"

        guard let url = URL(string: urlString) else {
            throw OutlookError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OutlookError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw OutlookError.tokenExpired
        }

        guard httpResponse.statusCode == 200 else {
            throw OutlookError.fetchFailed("Status code: \(httpResponse.statusCode)")
        }

        let decoder = JSONDecoder()
        let graphResponse = try decoder.decode(GraphCalendarResponse.self, from: data)

        return graphResponse.value.compactMap { event -> OutlookEvent? in
            guard let subject = event.subject else { return nil }

            let startDate = parseGraphDateTime(event.start)
            let endDate = parseGraphDateTime(event.end)

            guard let start = startDate, let end = endDate else { return nil }

            return OutlookEvent(
                id: event.id,
                subject: subject,
                startDateTime: start,
                endDateTime: end,
                isAllDay: event.isAllDay ?? false,
                isOnlineMeeting: event.isOnlineMeeting ?? false,
                attendeesCount: event.attendees?.count ?? 0,
                organizerEmail: event.organizer?.emailAddress.address,
                location: event.location?.displayName
            )
        }
    }

    @MainActor
    func fetchTodayEvents() async throws {
        isLoading = true
        defer { isLoading = false }

        let events = try await fetchEvents(for: Date())
        outlookEvents = events
    }

    func fetchTomorrowEvents() async throws -> [OutlookEvent] {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        return try await fetchEvents(for: tomorrow)
    }

    // MARK: - Helpers

    private func parseGraphDateTime(_ graphDateTime: GraphDateTime) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        // Try with microseconds first
        if let date = formatter.date(from: graphDateTime.dateTime) {
            return date
        }

        // Try without microseconds
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: graphDateTime.dateTime)
    }

    private func getRootViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return nil
        }
        return window.rootViewController
    }
}

// MARK: - Errors

enum OutlookError: LocalizedError {
    case notConfigured
    case noViewController
    case userCancelled
    case authFailed(String)
    case notSignedIn
    case tokenExpired
    case invalidURL
    case invalidResponse
    case fetchFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Microsoft authentication not configured. Please add your Client ID."
        case .noViewController:
            return "Unable to present sign-in screen"
        case .userCancelled:
            return "Sign-in was cancelled"
        case .authFailed(let message):
            return "Authentication failed: \(message)"
        case .notSignedIn:
            return "Not signed in to Outlook"
        case .tokenExpired:
            return "Session expired. Please sign in again."
        case .invalidURL:
            return "Invalid request URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .fetchFailed(let message):
            return "Failed to fetch calendar: \(message)"
        }
    }
}
