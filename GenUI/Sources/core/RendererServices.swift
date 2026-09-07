//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Host capabilities that catalog functions and components depend on.
///
/// Injecting these instead of calling platform APIs directly keeps formatting
/// and side effecting functions such as `openUrl` deterministic in tests, and
/// lets an app override behaviour (for example to open links in an in-app
/// browser).
public struct RendererServices {
    /// Opens a URL outside of the surface, subject to user activation.
    public var openUrl: (URL) -> Void

    /// Returns the current time, used by date formatting functions.
    public var now: () -> Date

    /// The locale used for number, currency and date formatting.
    public var locale: Locale

    /// The time zone used for date formatting.
    public var timeZone: TimeZone

    /// Creates a services container.
    /// Override any member to change renderer behaviour or make it testable.
    public init(
        openUrl: @escaping (URL) -> Void = RendererServices.openUrlWithSystem,
        now: @escaping () -> Date = Date.init,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) {
        self.openUrl = openUrl
        self.now = now
        self.locale = locale
        self.timeZone = timeZone
    }

    /// The default services, wired to the current platform.
    public static let `default` = RendererServices()

    /// Opens a URL with the platform's default handler.
    /// Used as the default implementation of ``openUrl``.
    public static func openUrlWithSystem(_ url: URL) {
        #if canImport(UIKit) && !os(watchOS)
        DispatchQueue.main.async {
            UIApplication.shared.open(url)
        }
        #elseif canImport(AppKit)
        NSWorkspace.shared.open(url)
        #else
        genUiLogger.warning("Opening URLs is not supported on this platform: \(url)")
        #endif
    }
}
