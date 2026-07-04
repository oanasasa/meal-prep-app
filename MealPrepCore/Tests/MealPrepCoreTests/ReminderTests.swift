import Testing
@testable import MealPrepCore

@Suite("Supplement & hydration reminders")
struct ReminderTests {

    @Test func supplementScheduleIsComplete() {
        let ids = Set(Reminders.supplements.map(\.id))
        #expect(ids == ["multivitamin", "top-minerals", "krill-oil", "creatine", "magnesium"])
    }

    @Test func breakfastSupplementsShareASlot() {
        let breakfast = Reminders.supplements.filter { $0.id == "multivitamin" || $0.id == "top-minerals" }
        for s in breakfast {
            #expect(s.cadence == .daily(TimeOfDay(7, 30)))
        }
    }

    @Test func creatineSwitchesGymVsRest() {
        let creatine = Reminders.supplements.first { $0.id == "creatine" }!
        // Monday (0) is a gym day → post-workout 18:45.
        #expect(Reminders.time(for: creatine, dayOffset: 0, thursdayGym: false) == TimeOfDay(18, 45))
        // Tuesday (1) is a rest day → 09:00.
        #expect(Reminders.time(for: creatine, dayOffset: 1, thursdayGym: false) == TimeOfDay(9, 0))
        // Thursday depends on the toggle.
        #expect(Reminders.time(for: creatine, dayOffset: 3, thursdayGym: false) == TimeOfDay(9, 0))
        #expect(Reminders.time(for: creatine, dayOffset: 3, thursdayGym: true) == TimeOfDay(18, 45))
    }

    @Test func gymDayOffsets() {
        #expect(Set(Reminders.gymDayOffsets(thursday: false)) == [0, 2, 4])
        #expect(Set(Reminders.gymDayOffsets(thursday: true)) == [0, 2, 3, 4])
    }

    @Test func hydrationDefaults() {
        #expect(Reminders.hydrationGoalMilliliters == 3000)
        #expect(Reminders.hydrationTimes.count == 3)
        #expect(Reminders.hydrationTimes.first == TimeOfDay(10, 0))
    }
}
