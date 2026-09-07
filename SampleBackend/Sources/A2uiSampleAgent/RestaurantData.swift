//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation

/// One item on a restaurant's menu.
public struct MenuItem: Codable, Equatable {
    /// A stable id, used as the option value in the order form.
    public let id: String

    /// The item's display name.
    public let name: String

    /// A short description shown under the name.
    public let description: String

    /// The item's price, in the restaurant's currency.
    public let price: Double

    /// A photo of the dish, shown on the order confirmation.
    ///
    /// Optional so a data set without photos still decodes; the bundled data
    /// has a photo for every dish.
    public let imageUrl: String?

    /// Creates a menu item.
    public init(id: String, name: String, description: String, price: Double, imageUrl: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.price = price
        self.imageUrl = imageUrl
    }
}

/// A restaurant the sample agent can order from.
public struct Restaurant: Codable, Equatable {
    /// A stable id, referenced by user actions.
    public let id: String

    /// The restaurant's name.
    public let name: String

    /// A short cuisine description, for example `"Chinese • Dim Sum"`.
    public let cuisine: String

    /// The city the restaurant is in.
    public let city: String

    /// The neighborhood the restaurant is in.
    public let neighborhood: String

    /// The average review score.
    public let rating: Double

    /// How many reviews the score is based on.
    public let reviewCount: Int

    /// A price range indicator, for example `"$$"`.
    public let priceRange: String

    /// The distance from the user, in miles.
    public let distanceMiles: Double

    /// How long the kitchen needs for an order, in minutes.
    public let prepMinutes: Int

    /// A photo of the restaurant.
    public let imageUrl: String

    /// The restaurant's menu.
    public let menu: [MenuItem]

    /// Whether the restaurant matches a free-text query.
    ///
    /// The match is deliberately forgiving: the sample agent has no language
    /// model, so it looks for any query word in the searchable fields.
    public func matches(query: String) -> Bool {
        let haystack = [name, cuisine, city, neighborhood].joined(separator: " ").lowercased()
        let words = Restaurant.searchWords(in: query)
        guard !words.isEmpty else { return true }
        return words.contains { haystack.contains($0) }
    }

    /// Extracts the meaningful words of a search query.
    /// Stop words and short tokens are dropped.
    public static func searchWords(in query: String) -> [String] {
        let stopWords: Set<String> = [
            "the", "a", "an", "and", "or", "in", "at", "for", "with", "near", "me", "my",
            "find", "show", "get", "order", "restaurant", "restaurants", "food", "top",
            "best", "please", "some", "want", "would", "like", "list", "place", "places"
        ]
        return query
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) && Int($0) == nil }
    }
}

/// Loads and queries the sample restaurant data.
public struct RestaurantCatalog {
    /// Every restaurant in the sample data set.
    public let restaurants: [Restaurant]

    /// Creates a catalog from an explicit list.
    /// Tests use this to control the data set.
    public init(restaurants: [Restaurant]) {
        self.restaurants = restaurants
    }

    /// Loads the bundled sample data.
    /// Throws when the bundled resource is missing or malformed.
    public init() throws {
        try self.init(bundle: .module)
    }

    /// Loads sample data from a specific bundle.
    /// Use this to supply an alternative `restaurants.json`.
    public init(bundle: Bundle) throws {
        guard let url = bundle.url(forResource: "restaurants", withExtension: "json") else {
            throw RestaurantCatalogError.resourceMissing
        }
        let data = try Data(contentsOf: url)
        restaurants = try JSONDecoder().decode([Restaurant].self, from: data)
    }

    /// Looks up a restaurant by id.
    public func restaurant(id: String) -> Restaurant? {
        restaurants.first { $0.id == id }
    }

    /// Returns the restaurants matching a query, best rated first.
    ///
    /// A query that matches nothing falls back to the whole list, so the demo
    /// always has something to show.
    public func search(_ query: String, limit: Int = 5) -> [Restaurant] {
        let matches = restaurants.filter { $0.matches(query: query) }
        let results = matches.isEmpty ? restaurants : matches
        return Array(results.sorted { $0.rating > $1.rating }.prefix(limit))
    }
}

/// Failures raised while loading the sample data.
public enum RestaurantCatalogError: Error, CustomStringConvertible {
    /// The bundled `restaurants.json` resource could not be found.
    case resourceMissing

    /// A human-readable description of the failure.
    public var description: String {
        switch self {
        case .resourceMissing:
            return "The bundled restaurants.json resource is missing from A2uiSampleAgent."
        }
    }
}
