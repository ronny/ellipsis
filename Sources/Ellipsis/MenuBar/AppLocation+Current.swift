import Foundation

extension AppLocation {
    /// A file reference to the bundle, taken at the first call. It follows
    /// the bundle when the Finder moves the running app; `Bundle.main`
    /// keeps the launch path.
    @MainActor private static let bundleReference = (Bundle.main.bundleURL as NSURL).fileReferenceURL() as NSURL?

    /// Where the running bundle is now.
    @MainActor static func current() -> AppLocation {
        let url = bundleReference?.filePathURL ?? Bundle.main.bundleURL
        return AppLocation(bundlePath: url.path, originalPath: translocationOriginal(of: url)?.path)
    }

    private typealias IsTranslocated = @convention(c) (
        CFURL, UnsafeMutablePointer<Bool>, UnsafeMutablePointer<Unmanaged<CFError>?>?
    ) -> DarwinBoolean
    private typealias OriginalPath = @convention(c) (
        CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?
    ) -> Unmanaged<CFURL>?

    /// The bundle macOS translocated `url` from, or nil when it is not
    /// translocated. The SecTranslocate calls are exported by
    /// Security.framework but have no public header. AppKit loads the
    /// framework, so `RTLD_NOLOAD` finds it.
    private static func translocationOriginal(of url: URL) -> URL? {
        guard
            let security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOW | RTLD_NOLOAD),
            let isSymbol = dlsym(security, "SecTranslocateIsTranslocatedURL"),
            let originalSymbol = dlsym(security, "SecTranslocateCreateOriginalPathForURL")
        else { return nil }
        let isTranslocated = unsafeBitCast(isSymbol, to: IsTranslocated.self)
        let originalPath = unsafeBitCast(originalSymbol, to: OriginalPath.self)
        var translocated = false
        guard isTranslocated(url as CFURL, &translocated, nil).boolValue, translocated else { return nil }
        return originalPath(url as CFURL, nil)?.takeRetainedValue() as URL?
    }
}
