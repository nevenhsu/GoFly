import Foundation
import Testing
@testable import GoFlyCore

@Suite
struct NoticeStateTests {
    @Test(arguments: DismissibleNotice.allCases)
    func aDismissedNoticeStaysHiddenUntilItOccursAgain(notice: DismissibleNotice) {
        var notices = NoticeState()
        #expect(!notices.isDismissed(notice))
        notices.dismiss(notice)
        #expect(notices.isDismissed(notice))

        notices.reopen(notice, ifPresent: Optional<String>.none)
        #expect(notices.isDismissed(notice), "Clearing the source does not reopen it")
        notices.reopen(notice, ifPresent: "new")
        #expect(!notices.isDismissed(notice))
    }

    @Test func dismissingOneNoticeLeavesTheOthersShown() {
        var notices = NoticeState()
        notices.dismiss(.routeError)
        for notice in DismissibleNotice.allCases where notice != .routeError {
            #expect(!notices.isDismissed(notice))
        }
        notices.reopen(.serviceError)
        #expect(notices.isDismissed(.routeError))
    }

    @Test func theUnconfirmedNoticeHidesOnlyForThePositionLeft() {
        var notices = NoticeState()
        let first = UUID(), second = UUID()
        #expect(notices.showsUnconfirmed(first))

        notices.leaveUnconfirmed(first)
        #expect(!notices.showsUnconfirmed(first))
        #expect(notices.showsUnconfirmed(second), "A new unconfirmed position shows again")
    }

    @Test func theFavoriteRouteFailureShowsUntilCleared() {
        var notices = NoticeState()
        #expect(notices.favoriteRouteKey == nil)
        notices.showFavoriteRouteFailure("route.favorite.saveFailed")
        #expect(notices.favoriteRouteKey == "route.favorite.saveFailed")
        notices.clearFavoriteRouteFailure()
        #expect(notices.favoriteRouteKey == nil)
    }
}
