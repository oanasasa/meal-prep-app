import Testing
@testable import MealPrepCore

@Suite("Cook schedule")
struct ScheduleTests {

    @Test func threeSessionsCoverMondayThroughSaturday() {
        let sessions = CookScheduler.sessions(gymThursday: false)
        #expect(sessions.count == 3)
        let covered = sessions.flatMap(\.coversDayOffsets).sorted()
        #expect(covered == [0, 1, 2, 3, 4, 5])   // Mon…Sat, disjoint & complete
        // Sunday (6) is intentionally uncovered — the tired day.
        #expect(!covered.contains(6))
    }

    @Test func sessionsNeverExceedTwoDays() {
        for gym in [false, true] {
            for s in CookScheduler.sessions(gymThursday: gym) {
                #expect(s.coversDayOffsets.count <= 2, "\(s.id) covers >2 days")
            }
        }
    }

    @Test func thursdayGymShiftsThirdSessionToFriday() {
        let noGym = CookScheduler.sessions(gymThursday: false)
        #expect(noGym[2].id == "thu")
        #expect(noGym[2].cookDayOffset == 3)   // Thursday

        let gym = CookScheduler.sessions(gymThursday: true)
        #expect(gym[2].id == "fri")
        #expect(gym[2].cookDayOffset == 4)     // shifted to Friday
        // Coverage is unchanged — still Friday + Saturday.
        #expect(gym[2].coversDayOffsets == [4, 5])
    }

    @Test func sessionLookupByDay() {
        #expect(CookScheduler.session(forDayOffset: 0, gymThursday: false)?.id == "sun-prep")
        #expect(CookScheduler.session(forDayOffset: 3, gymThursday: false)?.id == "tue")
        #expect(CookScheduler.session(forDayOffset: 4, gymThursday: false)?.id == "thu")
        #expect(CookScheduler.session(forDayOffset: 4, gymThursday: true)?.id == "fri")
        #expect(CookScheduler.session(forDayOffset: 6, gymThursday: false) == nil) // tired day
    }

    @Test func weekdayNames() {
        #expect(CookScheduler.weekdayName(forOffset: 0) == "Monday")
        #expect(CookScheduler.weekdayName(forOffset: -1) == "Sunday")
        #expect(CookScheduler.weekdayName(forOffset: 6) == "Sunday")
    }
}
