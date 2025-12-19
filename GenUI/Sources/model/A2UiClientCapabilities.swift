//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation

/// Describes the catalogs supported by the client.
/// Sent to the server to advertise available UI components.
public struct A2UiClientCapabilities {
    public let supportedCatalogIds: [String]
    public let inlineCatalogs: [JsonMap]?

    /// Creates a capabilities payload.
    /// Provide catalog ids and optionally inline catalog definitions.
    public init(supportedCatalogIds: [String], inlineCatalogs: [JsonMap]? = nil) {
        self.supportedCatalogIds = supportedCatalogIds
        self.inlineCatalogs = inlineCatalogs
    }

    /// Serializes the payload to a JSON map.
    /// The output is suitable for transport or logging.
    public func toJson() -> JsonMap {
        var json: JsonMap = ["supportedCatalogIds": supportedCatalogIds]
        if let inlineCatalogs {
            json["inlineCatalogs"] = inlineCatalogs
        }
        return json
    }
}
