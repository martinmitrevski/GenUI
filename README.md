# GenUI

GenUI is a Swift package and iOS sample app that implements Google's A2UI (Agent-to-UI) protocol for rendering agent-driven UI via SwiftUI.

The package is not official and it's still work in progress. Don't use it in production (for now).

## A2UI protocol overview

A2UI is a message-based protocol where an agent describes UI surfaces as JSON. The client receives messages that create surfaces, stream in component trees, mutate data models, and delete surfaces. Rendering is driven by a small set of message types such as `beginRendering`, `surfaceUpdate`, `dataModelUpdate`, and `deleteSurface`, typically transported over an A2A connection (see the A2A protocol overview at https://a2a.google.dev and the A2UI spec at https://a2a.google.dev/spec/a2ui).

## iOS implementation concepts

- `Catalog`: defines how A2UI component and style schemas map to SwiftUI builders. The catalog provides the runtime bridge between JSON component payloads and concrete SwiftUI views, including how children are built, how events are dispatched, and which styles are supported.
- `A2uiMessageProcessor`: parses incoming A2UI messages, maintains per-surface state (`UiDefinition` plus component registry), owns data models for each surface, and emits surface add/update/remove events when a surface is ready to render or changes.
- `GenUiSurface`: a SwiftUI view that subscribes to a surface definition, builds the component tree from the catalog, and dispatches UI events (like user actions) back to the host so they can be forwarded to the agent.
- `ContentGenerator` / `A2uiContentGenerator`: sends user messages to an A2UI agent over A2A, streams back A2UI message parts, and exposes separate streams for text responses and error handling. This is the bridge between the app and the agent.
- `GenUiConversation`: a facade that wires the generator to the message processor, tracks conversation history, forwards agent updates to surfaces, and provides a single host that the UI can bind to.

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
