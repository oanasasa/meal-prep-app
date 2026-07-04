import Foundation
import UserNotifications

enum NotificationRoute: Identifiable, Equatable {
    case cookMode(sessionID: String)
    case grocery

    var id: String {
        switch self {
        case .cookMode(let sessionID): return "cook-\(sessionID)"
        case .grocery: return "grocery"
        }
    }
}

/// Bridges UNUserNotificationCenter's delegate callbacks (foreground banners,
/// tap-to-open deep links) into SwiftUI. RootView observes `pendingRoute` and
/// presents the right screen.
@Observable
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    var pendingRoute: NotificationRoute?

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let route = info["route"] as? String else { return }
        switch route {
        case "cookMode":
            if let sessionID = info["sessionID"] as? String {
                pendingRoute = .cookMode(sessionID: sessionID)
            }
        case "grocery":
            pendingRoute = .grocery
        default:
            break
        }
    }
}
