//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Testing
@testable import GenUI

struct A2uiMessageTests {
    @Test func surfaceUpdateParsing() throws {
        let json: JsonMap = [
            "surfaceUpdate": [
                surfaceIdKey: "surface",
                "components": [
                    [
                        "id": "root",
                        "component": ["Text": ["text": "Hello"]]
                    ]
                ]
            ]
        ]

        let message = try A2uiMessageFactory.fromJson(json)
        #expect(message is SurfaceUpdate)
    }

    @Test func dataModelUpdateParsing() throws {
        let json: JsonMap = [
            "dataModelUpdate": [
                surfaceIdKey: "surface",
                "path": "/root",
                "contents": ["key": "value"]
            ]
        ]

        let message = try A2uiMessageFactory.fromJson(json)
        #expect(message is DataModelUpdate)
    }

    @Test func beginRenderingParsing() throws {
        let json: JsonMap = [
            "beginRendering": [
                surfaceIdKey: "surface",
                "root": "root"
            ]
        ]

        let message = try A2uiMessageFactory.fromJson(json)
        #expect(message is BeginRendering)
    }

    @Test func surfaceDeletionParsing() throws {
        let json: JsonMap = [
            "deleteSurface": [
                surfaceIdKey: "surface"
            ]
        ]

        let message = try A2uiMessageFactory.fromJson(json)
        #expect(message is SurfaceDeletion)
    }
}
