//
// Copyright © 2026 Martin Mitrevski. All rights reserved.
//

import Foundation
import SwiftUI
import Testing
@testable import GenUI

@Suite("What an agent writes and is told")
struct AgentPromptTests {
    @Test("A message counts once it is complete")
    func completeMessages() {
        let text = """
        {"version":"v1.0","createSurface":{"surfaceId":"a"}}
        {"version":"v1.0","updateComponents":{"surfaceId":"a","components":[{"id":"root","comp
        """

        #expect(A2uiStream.messages(in: text) == [#"{"version":"v1.0","createSurface":{"surfaceId":"a"}}"#])
    }

    @Test("Messages are read pretty-printed or in an array")
    func prettyMessages() {
        let pretty = """
        [
          {
            "createSurface": { "surfaceId": "a" }
          },
          { "deleteSurface": { "surfaceId": "a" } }
        ]
        """

        let messages = A2uiStream.messages(in: pretty)
        #expect(messages.count == 2)
        #expect(Json.decodeMap(messages[1])?.keys.first == "deleteSurface")
    }

    @Test("Braces and quotes in text are text")
    func bracesInText() {
        let text = #"{"text":"a } \" { b"} {"text":"c"}"#

        #expect(A2uiStream.messages(in: text) == [#"{"text":"a } \" { b"}"#, #"{"text":"c"}"#])
    }

    @Test("A portable component is named as the basic catalog names its own")
    func portableComponent() throws {
        let definition = try PortableComponent.definition([
            "name": "trip_map",
            "description": "A map of a plan",
            "parameters": [
                "type": "object",
                "properties": ["places": ["type": "array", "items": ["type": "string"]]],
                "required": ["places"]
            ],
            "events": [["name": "select_place", "description": "Tapping a pin asks about the place"]]
        ]) { _ in AnyView(EmptyView()) }

        #expect(definition.name == "TripMap")
        #expect(definition.description == "A map of a plan. Tapping a pin asks about the place.")
        #expect(definition.requiredProperties == ["places"])
        #expect(definition.propertySchema["places"]?["type"] as? String == "array")
    }

    @Test("A portable component needs a name")
    func unnamedPortableComponent() {
        #expect(throws: PortableComponentError.self) {
            try PortableComponent.definition(["description": "A map"]) { _ in AnyView(EmptyView()) }
        }
    }

    @Test("Problems say what would not render")
    func problems() {
        let catalog = BasicCatalog.catalog.adding(components: [], catalogId: "app")
        let text = """
        {"version":"v1.0","createSurface":{"surfaceId":"s","catalogId":"app"}}
        {"version":"v1.0","updateComponents":{"surfaceId":"s","components":[{"id":"root","component":"Column","children":["title","gone"]},{"id":"title","component":"Text","text":"Hi","size":2},{"id":"map","component":"Map"},{"id":"lost","component":"Divider"}]}}
        """

        #expect(A2uiProgram.problems(in: text, catalog: catalog) == [
            "map is a Map, which the catalog doesn't have",
            "title is a Text, which has no size",
            "root holds gone, which is not defined",
            "lost is defined but nothing holds it",
            "map is defined but nothing holds it"
        ])
    }

    @Test("The tabs of a container are followed")
    func tabs() {
        let catalog = BasicCatalog.catalog.adding(components: [], catalogId: "app")
        let text = """
        {"version":"v1.0","createSurface":{"surfaceId":"s","catalogId":"app","components":[{"id":"root","component":"Tabs","tabs":[{"title":"One","child":"one"}]},{"id":"one","component":"Text","text":"1"}]}}
        """

        #expect(A2uiProgram.problems(in: text, catalog: catalog).isEmpty)
    }

    @Test("Instructions say how a reply carries its UI, then the protocol, catalog, rules and examples")
    func instructions() {
        let catalog = BasicCatalog.catalog.adding(components: [], catalogId: "app")
        let text = A2uiInstructions(
            catalog: catalog,
            fence: "ui:a2ui@1.0",
            preamble: "Plan trips as UI.",
            rules: ["Keep it short."],
            examples: ["An example."]
        ).text

        let order = ["Plan trips as UI.", "`ui:a2ui@1.0`", A2uiPromptBuilder.protocolOverview, "## The catalog `app`", "1. Keep it short.", "## Examples\n\nAn example."]
        let positions = order.map { text.range(of: $0)?.lowerBound }
        #expect(positions.allSatisfy { $0 != nil })
        #expect(positions.compactMap { $0 } == positions.compactMap { $0 }.sorted())
    }
}
