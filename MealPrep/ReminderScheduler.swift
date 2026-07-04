import Foundation
import UserNotifications
import MealPrepCore

/// Schedules the trainer's supplement + hydration reminders as repeating local
/// notifications (no server). Daily-cadence supplements repeat every day;
/// creatine repeats weekly on gym vs rest days at different times; hydration
/// fires a few spaced times a day.
enum ReminderScheduler {

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Rebuild the whole schedule from scratch (call on launch and whenever the
    /// gym-Thursday toggle or reminder times change).
    static func reschedule(thursdayGym: Bool, hydration: Bool = true) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        for supp in Reminders.supplements {
            switch supp.cadence {
            case .daily(let t):
                add(id: "supp-\(supp.id)", title: supp.name, body: supp.note,
                    dateComponents: DateComponents(hour: t.hour, minute: t.minute), center: center)
            case .gymVsRest(let gym, let rest):
                // One weekly-repeating trigger per weekday, at the right time.
                for offset in 0...6 {
                    let onGymDay = Reminders.gymDayOffsets(thursday: thursdayGym).contains(offset)
                    let t = onGymDay ? gym : rest
                    var dc = DateComponents(hour: t.hour, minute: t.minute)
                    dc.weekday = weekday(fromMondayOffset: offset)
                    add(id: "supp-\(supp.id)-d\(offset)", title: supp.name,
                        body: onGymDay ? supp.note + " (post-workout)" : supp.note,
                        dateComponents: dc, center: center)
                }
            }
        }

        if hydration {
            for (i, t) in Reminders.hydrationTimes.enumerated() {
                add(id: "hydration-\(i)", title: "Hydration 💧",
                    body: "Drink water — goal \(Reminders.hydrationGoalMilliliters / 1000) L today.",
                    dateComponents: DateComponents(hour: t.hour, minute: t.minute), center: center)
            }
        }
    }

    // Calendar weekday: 1 = Sunday … 7 = Saturday, from Monday-based offset.
    private static func weekday(fromMondayOffset offset: Int) -> Int {
        offset == 6 ? 1 : offset + 2
    }

    private static func add(id: String, title: String, body: String,
                            dateComponents: DateComponents,
                            center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
