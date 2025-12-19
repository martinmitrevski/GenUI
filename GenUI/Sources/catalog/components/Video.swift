//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import SwiftUI

public let video = CatalogItem(
    name: "Video",
    dataSchema: S.object(
        properties: [
            "url": A2uiSchemas.stringReference(description: "The URL of the video to play.")
        ],
        required: ["url"]
    ),
    widgetBuilder: { _ in
        AnyView(
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                    .frame(width: 200, height: 100)
                Text("Video")
                    .font(.caption)
            }
        )
    },
    exampleData: [
        {
            """
            [
              {
                "id": "root",
                "component": {
                  "Video": {
                    "url": {
                      "literalString": "https://example.com/video.mp4"
                    }
                  }
                }
              }
            ]
            """
        }
    ]
)
