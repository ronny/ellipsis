import Foundation
import Testing
@testable import Ellipsis

/// Runs `AppInstaller` against fake bundles in a temporary folder that
/// stands in for `/Applications`.
final class AppInstallerTests {
    private let root: URL
    private let applications: URL
    private let downloads: URL
    private let installer: AppInstaller

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AppInstallerTests.\(UUID().uuidString)")
        applications = root.appendingPathComponent("Applications")
        downloads = root.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        installer = AppInstaller(applications: applications)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func makeBundle(
        in folder: URL, id: String = "au.ronny.Ellipsis", version: String = "1.0.0", build: String = "1"
    ) throws -> URL {
        let bundle = folder.appendingPathComponent("Ellipsis.app")
        let contents = bundle.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(
            at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true
        )
        let plist: [String: String] = [
            "CFBundleIdentifier": id, "CFBundleShortVersionString": version, "CFBundleVersion": build,
        ]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        try Data("binary".utf8).write(to: contents.appendingPathComponent("MacOS/Ellipsis"))
        return bundle
    }

    private func quarantine(_ url: URL) {
        let value = "0083;6ac9934c;Safari;"
        let result = value.withCString { setxattr(url.path, AppInstaller.quarantineAttribute, $0, strlen($0), 0, 0) }
        #expect(result == 0)
        #expect(isQuarantined(url))
    }

    private func isQuarantined(_ url: URL) -> Bool {
        getxattr(url.path, AppInstaller.quarantineAttribute, nil, 0, 0, 0) >= 0
    }

    private func version(of bundle: URL) -> String? {
        AppInstaller.info(of: bundle)?.version
    }

    @Test func aBundleInApplicationsInstallsInPlace() throws {
        let bundle = try makeBundle(in: applications)
        guard case .inPlace(let destination) = try installer.plan(source: bundle) else {
            Issue.record("expected an in-place install")
            return
        }
        #expect(destination.path == bundle.path)
    }

    @Test func anotherSpellingOfTheSameFolderInstallsInPlace() throws {
        let bundle = try makeBundle(in: applications)
        let link = root.appendingPathComponent("Link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: applications)
        let spelled = link.appendingPathComponent("Ellipsis.app")
        guard case .inPlace(let destination) = try installer.plan(source: spelled) else {
            Issue.record("expected an in-place install")
            return
        }
        #expect(destination.lastPathComponent == bundle.lastPathComponent)
        try installer.install(installer.plan(source: spelled))
        #expect(FileManager.default.fileExists(atPath: bundle.path))
    }

    @Test func anInPlaceInstallClearsTheQuarantine() throws {
        let bundle = try makeBundle(in: applications)
        quarantine(bundle)
        quarantine(bundle.appendingPathComponent("Contents/Info.plist"))
        try installer.install(installer.plan(source: bundle))
        #expect(!isQuarantined(bundle))
        #expect(!isQuarantined(bundle.appendingPathComponent("Contents/Info.plist")))
    }

    @Test func aRemovedSourceIsRefused() throws {
        let bundle = try makeBundle(in: downloads)
        try FileManager.default.removeItem(at: bundle)
        #expect(throws: AppInstaller.Failure.sourceMissing(bundle.path)) {
            try self.installer.plan(source: bundle)
        }
    }

    @Test func aDifferentAppAtTheDestinationIsRefused() throws {
        let source = try makeBundle(in: downloads)
        try makeBundle(in: applications, id: "com.example.Other")
        #expect(throws: AppInstaller.Failure.differentApp(existing: "com.example.Other")) {
            try self.installer.plan(source: source)
        }
    }

    @Test func aCopyToAnEmptyFolderNeedsNoReplace() throws {
        let source = try makeBundle(in: downloads)
        let plan = try installer.plan(source: source)
        guard case .copy(_, let destination, let existing, _) = plan else {
            Issue.record("expected a copy")
            return
        }
        #expect(existing == nil)
        try installer.install(plan)
        #expect(version(of: destination) == "1.0.0")
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test func aCopyReplacesAnOlderCopyAndClearsTheQuarantine() throws {
        let source = try makeBundle(in: downloads, version: "1.1.0", build: "2")
        quarantine(source)
        let destination = try makeBundle(in: applications, version: "1.0.0", build: "1")
        let plan = try installer.plan(source: source)
        guard case .copy(_, _, let existing?, let incoming) = plan else {
            Issue.record("expected a copy over an existing app")
            return
        }
        #expect(!existing.isNewer(than: incoming))
        try installer.install(plan)
        #expect(version(of: destination) == "1.1.0")
        #expect(!isQuarantined(destination))
    }

    @Test func aNewerCopyAtTheDestinationIsReported() throws {
        let source = try makeBundle(in: downloads, version: "1.0.0", build: "1")
        try makeBundle(in: applications, version: "1.10.0", build: "12")
        guard case .copy(_, _, let existing?, let incoming) = try installer.plan(source: source) else {
            Issue.record("expected a copy over an existing app")
            return
        }
        #expect(existing.isNewer(than: incoming))
    }

    @Test func aFailedCopyKeepsTheOldCopy() throws {
        let source = try makeBundle(in: downloads, version: "1.1.0")
        let unreadable = source.appendingPathComponent("Contents/MacOS/Ellipsis")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: unreadable.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unreadable.path) }
        let destination = try makeBundle(in: applications, version: "1.0.0")
        let plan = try installer.plan(source: source)
        #expect(throws: (any Error).self) {
            try self.installer.install(plan)
        }
        #expect(version(of: destination) == "1.0.0")
        #expect(try FileManager.default.contentsOfDirectory(atPath: applications.path) == ["Ellipsis.app"])
    }

    @Test func versionsCompareAsNumbers() {
        let old = AppInstaller.Info(bundleIdentifier: "a", version: "1.9.0", build: "9")
        let new = AppInstaller.Info(bundleIdentifier: "a", version: "1.10.0", build: "10")
        #expect(new.isNewer(than: old))
        #expect(!old.isNewer(than: new))
        #expect(!old.isNewer(than: old))
    }

    @Test func aHigherBuildOfTheSameVersionIsNewer() {
        let old = AppInstaller.Info(bundleIdentifier: "a", version: "1.0.0", build: "3")
        let new = AppInstaller.Info(bundleIdentifier: "a", version: "1.0.0", build: "4")
        #expect(new.isNewer(than: old))
    }
}
