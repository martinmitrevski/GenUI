//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation

/// Describes which catalogs a client supports.
/// Used to inform the server about available UI components.
public struct A2UiClientCapabilities {
    public let supportedCatalogIds: [String]
    public let inlineCatalogs: [JsonMap]?

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(supportedCatalogIds: [String], inlineCatalogs: [JsonMap]? = nil) {
        self.supportedCatalogIds = supportedCatalogIds
        self.inlineCatalogs = inlineCatalogs
    }

    /// Serializes the value to a JSON-compatible dictionary.
    /// The output is suitable for transport or logging.
    public func toJson() -> JsonMap {
        var json: JsonMap = ["supportedCatalogIds": supportedCatalogIds]
        if let inlineCatalogs {
            json["inlineCatalogs"] = inlineCatalogs
        }
        return json
    }
}
