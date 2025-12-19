//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Testing
@testable import GenUI

struct ToolsTests {
    @Test func surfaceUpdateToolInvokesHandler() async {
        var captured: [A2uiMessage] = []
        let tool = SurfaceUpdateTool(handleMessage: { captured.append($0) }, catalog: Catalog([]))

        let args: JsonMap = [
            surfaceIdKey: "surface",
            "components": [
                ["id": "root", "component": ["Text": [:]]]
            ]
        ]
        let response = await tool.invoke(args)

        #expect(captured.count == 1)
        #expect(response[surfaceIdKey] as? String == "surface")
    }

    @Test func deleteSurfaceToolInvokesHandler() async {
        var captured: [A2uiMessage] = []
        let tool = DeleteSurfaceTool(handleMessage: { captured.append($0) })

        let response = await tool.invoke([surfaceIdKey: "surface"])

        #expect(captured.count == 1)
        #expect(response["status"] as? String != nil)
    }

    @Test func beginRenderingToolInvokesHandler() async {
        var captured: [A2uiMessage] = []
        let tool = BeginRenderingTool(handleMessage: { captured.append($0) }, catalogId: "catalog")

        let response = await tool.invoke([surfaceIdKey: "surface", "root": "root"])

        #expect(captured.count == 1)
        #expect(response["status"] as? String != nil)
    }
}
