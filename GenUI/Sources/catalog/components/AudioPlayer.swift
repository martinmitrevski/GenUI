//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import SwiftUI

public let audioPlayer = CatalogItem(
    name: "AudioPlayer",
    dataSchema: S.object(
        properties: [
            "url": A2uiSchemas.stringReference(description: "The URL of the audio to play.")
        ],
        required: ["url"]
    ),
    widgetBuilder: { _ in
        AnyView(
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                    .frame(width: 200, height: 100)
                Text("AudioPlayer")
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
                  "AudioPlayer": {
                    "url": {
                      "literalString": "https://example.com/audio.mp3"
                    }
                  }
                }
              }
            ]
            """
        }
    ]
)
