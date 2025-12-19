# GenUI

GenUI is a Swift package and iOS sample app that implements Google's A2UI (Agent-to-UI) protocol for rendering agent-driven UI via SwiftUI.

The package is not official and it's still work in progress. Don't use it in production (for now).

## What's in this repo

- `GenUI/`: the Swift package that implements the A2UI protocol, rendering, and A2A client/connector.
- `GenUISample/`: a SwiftUI sample app (Restaurant Finder) that uses the GenUI SDK and talks to a local A2A server.
- `GenUITests/`: Swift Testing coverage for the SDK.

## Installation

### Swift Package Manager

Use this repository as a Swift Package dependency and add `GenUI` to your target.

```
https://github.com/martinmitrevski/GenUI.git
```

You can also use the local `Package.swift` in this repo directly during development.

## Example usage

```swift
import GenUI
import SwiftUI

let catalog = CoreCatalogItems.asCatalog()
let processor = A2uiMessageProcessor(catalogs: [catalog])
let generator = A2uiContentGenerator(serverUrl: URL(string: "http://localhost:10002")!)

let conversation = GenUiConversation(
    contentGenerator: generator,
    a2uiMessageProcessor: processor
)

struct DemoView: View {
    var body: some View {
        GenUiSurface(host: conversation.host, surfaceId: "default")
            .task {
                await conversation.sendRequest(UserMessage.text("Top 5 Chinese restaurants in New York."))
            }
    }
}
```
