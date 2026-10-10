import Testing
@testable import Ellipsis

struct AppLocationTests {
    private let own = "au.ronny.Ellipsis"

    @Test func inApplicationsCanHide() {
        #expect(AppLocation(bundlePath: "/Applications/Ellipsis.app", originalPath: nil).canHide)
    }

    @Test func aTrailingSlashStillCounts() {
        #expect(AppLocation(bundlePath: "/Applications/Ellipsis.app/", originalPath: nil).canHide)
    }

    @Test func aBuildFolderCannotHide() {
        #expect(!AppLocation(bundlePath: "/Users/me/ellipsis/build/Ellipsis.app", originalPath: nil).canHide)
    }

    @Test func downloadsCannotHide() {
        #expect(!AppLocation(bundlePath: "/Users/me/Downloads/Ellipsis.app", originalPath: nil).canHide)
    }

    @Test func aSubfolderOfApplicationsCannotHide() {
        // Untested with MenuBarAgent, so it does not count.
        #expect(!AppLocation(bundlePath: "/Applications/Utilities/Ellipsis.app", originalPath: nil).canHide)
    }

    @Test func userApplicationsCannotHide() {
        #expect(!AppLocation(bundlePath: "/Users/me/Applications/Ellipsis.app", originalPath: nil).canHide)
    }

    @Test func aPathThatOnlyLooksLikeApplicationsCannotHide() {
        #expect(!AppLocation(bundlePath: "/Applications/../tmp/Ellipsis.app", originalPath: nil).canHide)
        #expect(!AppLocation(bundlePath: "/ApplicationsX/Ellipsis.app", originalPath: nil).canHide)
    }

    @Test func translocatedFromApplicationsCannotHide() {
        let location = AppLocation(
            bundlePath: "/private/var/folders/mb/x/T/AppTranslocation/E916/d/Ellipsis.app",
            originalPath: "/Applications/Ellipsis.app"
        )
        #expect(location.isTranslocated)
        #expect(!location.canHide)
    }

    @Test func nothingHidesWhereTheIconCannotBeAllowListed() {
        let location = AppLocation(bundlePath: "/Users/me/Downloads/Ellipsis.app", originalPath: nil)
        #expect(location.identifiersToHide(["a", "b"], own: own).isEmpty)
    }

    @Test func theWantedSetHidesFromApplications() {
        let location = AppLocation(bundlePath: "/Applications/Ellipsis.app", originalPath: nil)
        #expect(location.identifiersToHide(["a", "b"], own: own) == ["a", "b"])
    }

    @Test func ellipsisNeverHidesItself() {
        let location = AppLocation(bundlePath: "/Applications/Ellipsis.app", originalPath: nil)
        #expect(location.identifiersToHide(["a", own], own: own) == ["a"])
    }

    @Test func aMoveFromDownloadsCopiesToApplications() {
        let location = AppLocation(bundlePath: "/Users/me/Downloads/Ellipsis.app", originalPath: nil)
        #expect(location.source == "/Users/me/Downloads/Ellipsis.app")
        #expect(location.destination == "/Applications/Ellipsis.app")
        #expect(location.needsCopy)
    }

    @Test func aMoveOfATranslocatedCopyStartsFromTheOriginal() {
        let location = AppLocation(
            bundlePath: "/private/var/folders/mb/x/T/AppTranslocation/E916/d/EllipsisDev.app",
            originalPath: "/Users/me/Downloads/EllipsisDev.app"
        )
        #expect(location.source == "/Users/me/Downloads/EllipsisDev.app")
        #expect(location.destination == "/Applications/EllipsisDev.app")
        #expect(location.appName == "EllipsisDev")
        #expect(location.needsCopy)
    }

    @Test func aTranslocatedAppAlreadyInApplicationsNeedsNoCopy() {
        let location = AppLocation(
            bundlePath: "/private/var/folders/mb/x/T/AppTranslocation/E916/d/Ellipsis.app",
            originalPath: "/Applications/Ellipsis.app"
        )
        #expect(location.destination == "/Applications/Ellipsis.app")
        #expect(!location.needsCopy)
    }
}
