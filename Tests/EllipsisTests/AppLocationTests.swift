import Foundation
import Testing
@testable import Ellipsis

/// `canHide` compares the bundle's folder with `/Applications` on disk, so
/// these tests read the real file system.
struct AppLocationTests {
    private let own = "au.ronny.Ellipsis"

    private func canHide(_ path: String) -> Bool {
        AppLocation(bundlePath: path, originalPath: nil).canHide
    }

    @Test func inApplicationsCanHide() {
        #expect(canHide("/Applications/Ellipsis.app"))
    }

    @Test func aTrailingSlashStillCounts() {
        #expect(canHide("/Applications/Ellipsis.app/"))
    }

    @Test func theDataVolumePathOfApplicationsCounts() {
        #expect(canHide("/System/Volumes/Data/Applications/Ellipsis.app"))
    }

    @Test func applicationsInTheWrongCaseCounts() {
        #expect(canHide("/applications/Ellipsis.app"))
    }

    @Test func aBuildFolderCannotHide() {
        #expect(!canHide("/Users/me/ellipsis/build/Ellipsis.app"))
    }

    @Test func downloadsCannotHide() {
        #expect(!canHide("/Users/me/Downloads/Ellipsis.app"))
    }

    @Test func aDiskImageCannotHide() {
        #expect(!canHide("/Volumes/Ellipsis/Ellipsis.app"))
    }

    @Test func aSubfolderOfApplicationsCannotHide() {
        // Untested with MenuBarAgent, so it does not count.
        #expect(!canHide("/Applications/Utilities/Ellipsis.app"))
    }

    @Test func userApplicationsCannotHide() {
        #expect(!canHide(NSHomeDirectory() + "/Applications/Ellipsis.app"))
    }

    @Test func aPathThatOnlyLooksLikeApplicationsCannotHide() {
        #expect(!canHide("/Applications/../tmp/Ellipsis.app"))
        #expect(!canHide("/ApplicationsX/Ellipsis.app"))
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

    @Test func withoutAnOwnIdentifierTheWantedSetHides() {
        let location = AppLocation(bundlePath: "/Applications/Ellipsis.app", originalPath: nil)
        #expect(location.identifiersToHide(["a", own], own: nil) == ["a", own])
    }

    @Test func theSourceOfAPlainCopyIsTheBundle() {
        let location = AppLocation(bundlePath: "/Users/me/Downloads/Ellipsis.app", originalPath: nil)
        #expect(location.source == "/Users/me/Downloads/Ellipsis.app")
        #expect(location.appName == "Ellipsis")
    }

    @Test func theSourceOfATranslocatedCopyIsTheOriginal() {
        let location = AppLocation(
            bundlePath: "/private/var/folders/mb/x/T/AppTranslocation/E916/d/EllipsisDev.app",
            originalPath: "/Users/me/Downloads/EllipsisDev.app"
        )
        #expect(location.source == "/Users/me/Downloads/EllipsisDev.app")
        #expect(location.appName == "EllipsisDev")
    }
}
