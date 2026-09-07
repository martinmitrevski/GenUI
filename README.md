# GenUI

GenUI is a Swift package that implements the **[A2UI (Agent to UI) protocol, version 1.0](https://github.com/a2ui-project/a2ui)**
for SwiftUI, plus a runnable sample agent so you can see the whole loop working
in a few seconds.

A2UI lets an agent describe a user interface as a stream of JSON messages. The
renderer builds the UI, keeps a local data model, validates input, and sends
user actions and function calls back to the agent. This repository contains a
complete renderer for the v1.0 basic catalog, the A2A transport binding, and a
restaurant-ordering agent that exercises every part of the protocol.

> This package is not an official A2UI implementation. It tracks the v1.0
> release candidate of the specification.

## What's new

This release upgrades the implementation from A2UI v0.8 to **v1.0**:

| Area | v0.8 (previous) | v1.0 (now) |
| --- | --- | --- |
| Messages | `beginRendering`, `surfaceUpdate`, `dataModelUpdate`, `deleteSurface` | `createSurface`, `updateComponents`, `updateDataModel`, `deleteSurface`, `callRendererFunction`, `agentFunctionResponse` |
| Envelope | no version field | every message carries `"version": "v1.0"` |
| Components | nested wrapper `{"component": {"Text": {…}}}` | flat `{"id": …, "component": "Text", "text": …}` |
| Values | `{"literalString": …}` / `{"path": …}` | literal, `{"path": …}` or `{"call": …, "args": …}` |
| Children | `{"explicitList": […]}` / `{"template": {…}}` | `["a", "b"]` or `{"componentId": …, "path": …}` |
| Functions | none | 14 catalog functions, `@index`, and bidirectional function calls |
| Validation | `validationRegexp` on a text field | `checks` with `ValidationResult` on any input and on `Button` |
| Composition | not validated | `allowedParents` / `allowedChildren` with `UNALLOWED_PARENT` / `UNALLOWED_CHILD` errors |
| Styling | `styles` with brand colours | removed; the platform theme decides |
| Capabilities | `a2uiClientCapabilities` | `a2uiRendererCapabilities`, `a2uiRendererDataModel`, agent-card extension params |
| Backend | external | `swift run a2ui-sample-server` in this repository |

See [Migrating from v0.8](#migrating-from-v08) for the API changes.

## Quick start

Run the agent, then run the app:

```bash
# Terminal 1: the sample agent on http://localhost:10002
swift run a2ui-sample-server

# Terminal 2: the iOS sample app
open GenUI.xcodeproj    # run the GenUISample scheme
```

Ask for something like *"Top 5 Chinese restaurants in New York"*. The agent
renders a list of restaurants; picking one renders an order form with live
validation; placing the order renders a confirmation.

The server has no dependencies and needs no API keys: it is a deterministic
agent, so the sample behaves the same every time.

## Installation

Add the package with Swift Package Manager:

```swift
.package(url: "https://github.com/martinmitrevski/GenUI.git", branch: "main")
```

and depend on the `GenUI` product. Platforms: iOS 15+, macOS 13+, tvOS 15+,
visionOS 1+.

## Usage

```swift
import GenUI
import SwiftUI

@MainActor
final class ChatModel: ObservableObject {
    let conversation: GenUiConversation
    @Published var surfaceIds: [String] = []

    init() {
        conversation = GenUiConversation(
            contentGenerator: A2uiContentGenerator(serverUrl: URL(string: "http://localhost:10002")!),
            processor: A2uiMessageProcessor(
                catalogs: [BasicCatalog.catalog],
                defaultCatalogId: BasicCatalog.catalogId
            )
        )
        conversation.onSurfaceAdded = { [weak self] in self?.surfaceIds.append($0.surfaceId) }
        conversation.onSurfaceRemoved = { [weak self] update in
            self?.surfaceIds.removeAll { $0 == update.surfaceId }
        }
    }

    func ask(_ prompt: String) async {
        await conversation.send(text: prompt)
    }
}

struct ChatView: View {
    @StateObject private var model = ChatModel()

    var body: some View {
        ScrollView {
            ForEach(model.surfaceIds, id: \.self) { surfaceId in
                GenUiSurface(host: model.conversation.host, surfaceId: surfaceId) {
                    AnyView(ProgressView())
                }
            }
        }
        .task { await model.ask("Top 5 Chinese restaurants in New York") }
    }
}
```

`GenUiConversation` handles the return channel for you: user actions, renderer
function results and renderer errors are batched and sent back to the agent with
the renderer capabilities and, for surfaces created with `sendDataModel`, their
current data models.

## Architecture

```
Agent ──A2A/JSON-RPC──▶ A2uiAgentConnector ──▶ A2uiContentGenerator
                                                      │  A2uiMessage
                                                      ▼
                        GenUiConversation ──▶ A2uiMessageProcessor ──▶ SurfaceViewModel
                                ▲                     │                      │
                     RendererMessage                  │ Catalog              ▼
                                └──── actions, function calls, errors ── GenUiSurface
```

| Type | Responsibility |
| --- | --- |
| `A2uiMessage`, `RendererMessage` | The v1.0 wire messages, in both directions, with decoding and encoding. |
| `Component`, `UiDefinition` | The flat adjacency list of a surface and its component tree. |
| `DataModel`, `DataContext`, `DataPath` | The surface's JSON data model, JSON Pointer addressing and collection scopes. |
| `DynamicValue`, `FunctionCall`, `ChildList`, `CheckRule` | Property values: literals, data bindings, function calls, templates and validation rules. |
| `Catalog`, `ComponentDefinition`, `FunctionDefinition`, `CatalogRegistry` | What the renderer supports, and how components and functions resolve per surface. |
| `BasicCatalog` | The v1.0 basic catalog, implemented in SwiftUI. |
| `ExpressionEvaluator` | Evaluates bindings, function calls, `formatString` templates and checks. |
| `A2uiMessageProcessor` | Applies messages, owns surface state, executes agent-initiated function calls and routes unknown functions to the agent. |
| `GenUiSurface`, `SurfaceRenderer`, `ComponentRenderContext` | Renders a surface and gives components resolved properties, children, bindings and actions. |
| `A2uiAgentConnector`, `A2uiContentGenerator` | The A2A binding: extension activation, metadata, and `application/a2ui+json` data parts. |
| `GenUiConversation` | Wires an agent to a renderer and keeps the conversation history. |
| `A2uiPromptBuilder` | Builds the system prompt and catalog documents for LLM-driven agents. |

## The basic catalog

All 18 components and 14 functions of the v1.0 basic catalog are implemented:

**Components** — `Text`, `Image`, `Icon`, `Video`, `AudioPlayer`, `Row`,
`Column`, `List`, `Card`, `Tabs`, `Modal`, `Divider`, `Button`, `TextField`,
`CheckBox`, `ChoicePicker`, `Slider`, `DateTimeInput`.

**Functions** — `required`, `regex`, `length`, `numeric`, `email`,
`formatString`, `formatNumber`, `formatCurrency`, `formatDate`, `pluralize`,
`openUrl`, `and`, `or`, `not`, plus the `@index` system function.

`Text` renders the Markdown subset the specification allows (headings, emphasis,
lists and quotes), because the catalog only exposes `body` and `caption`
variants.

### Data binding and templates

```json
{"id": "menu", "component": "List", "children": {"componentId": "row", "path": "/items"}}
{"id": "row", "component": "Text", "text": {"path": "name"}}
```

Inside a template, relative paths resolve against the current item and `@index`
returns its position. Absolute paths still reach the root of the data model.

Input components (`TextField`, `CheckBox`, `ChoicePicker`, `Slider`,
`DateTimeInput`) write straight back into the data model, so a `Text` bound to
the same path updates as the user types. Nothing is sent to the agent until an
action fires.

### Validation

```json
"checks": [
  {"condition": {"call": "required", "args": {"value": {"path": "/order/items"}}},
   "message": "Pick at least one dish."}
]
```

Failing checks are shown under the input. A `Button` with failing checks
disables itself and shows the message, so the agent can express "submit is only
allowed when…" declaratively.

### Bidirectional function calls

* The agent can invoke a renderer function with `callRendererFunction`; the
  renderer answers with `rendererFunctionResponse`, and refuses functions that
  are `rendererOnly` with `INVALID_FUNCTION_CALL`.
* A function referenced in a component tree that the renderer does not know is
  routed to the agent as `callAgentFunction`. The binding renders as pending
  until the `agentFunctionResponse` arrives, then re-renders with the value.

The sample agent uses this for the fulfilment estimate on the order form.

### Extending the catalog

```swift
let heroCard = ComponentDefinition(
    name: "HeroCard",
    properties: ["title": JsonSchema.dynamicString(), "child": JsonSchema.child()],
    required: ["title", "child"],
    allowedParents: ["Surface"]
) { context in
    AnyView(
        VStack(alignment: .leading) {
            Text(context.string("title", default: ""))
            context.childView(context.childId())
        }
    )
}

let catalog = BasicCatalog.catalog.adding(
    components: [heroCard],
    catalogId: "mycompany.com:app-catalog"
)
```

`catalog.toJsonSchema()` produces a spec-compliant catalog document you can send
to an agent as an inline catalog (`RendererCapabilities(inlineCatalogs:)`) or
embed in a prompt with `A2uiPromptBuilder`.

`DebugCatalogView(catalog:)` renders every component's examples, which is handy
while building your own catalog.

## The sample backend

`SampleBackend/` contains a deterministic A2UI agent and a dependency-free A2A
server. See [SampleBackend/README.md](SampleBackend/README.md) for the endpoints,
the message flow and the command line options.

```bash
swift run a2ui-sample-server --port 10002 --host localhost
curl http://localhost:10002/.well-known/agent-card.json
```

The agent is also available as the `A2uiSampleAgent` library, so you can drive it
in process — the end-to-end tests do exactly that.

## Testing

```bash
swift test                                                    # 220+ tests, macOS
xcodebuild -scheme GenUI -destination 'platform=iOS Simulator,name=iPhone 16' test
```

The suite covers the protocol model, data model and JSON Pointer semantics, the
expression evaluator and every catalog function, catalog resolution and
composition rules, the renderer, the message processor including bidirectional
function calls, the A2A binding, the conversation facade, the sample agent, and
an end-to-end run of the whole ordering flow over the A2A encoding. Payloads
taken from the specification's own examples are used as conformance fixtures.

## Migrating from v0.8

The protocol change is breaking, and so is the API:

* `A2uiMessageProcessor(catalogs:)` now takes `[Catalog]` built from
  `ComponentDefinition`s; `CoreCatalogItems.asCatalog()` became
  `BasicCatalog.catalog`.
* `GenUiSurface(host:surfaceId:defaultBuilder:)` is now
  `GenUiSurface(host:surfaceId:placeholder:)`.
* `GenUiConversation(contentGenerator:a2uiMessageProcessor:handleSubmitEvents:)`
  is now `GenUiConversation(contentGenerator:processor:forwardsRendererMessages:)`,
  and `sendRequest(_:)` became `send(_:)` / `send(text:)`.
* `ContentGenerator` takes a `GenerationRequest` and publishes `messages`,
  `textResponses` and `errors`.
* `UiEvent`/`UserActionEvent` were replaced by `RendererMessage` and
  `RendererAction`, which match the wire format.
* Catalog items are now `ComponentDefinition`s with a JSON Schema and a
  `ComponentRenderContext`-based builder; the old `CatalogItem`,
  `Schema`/`S` builders, `AiTool` types and `A2uiSchemas` were removed. Use
  `JsonSchema` and `A2uiPromptBuilder` instead.
* The v0.8 `styles` payload is gone: surfaces inherit the app's SwiftUI theme.

## Known limitations

* `Icon` supports the catalog's named icons (mapped to SF Symbols); inline
  `svgPath` icons are not rendered.
* `pluralize` selects the `zero`, `one`, `two` and `other` CLDR categories;
  languages needing `few`/`many` fall back to `other`.
* A vertical `List` grows with its content instead of scrolling, so it composes
  inside a scrollable host; horizontal lists scroll.
* `Image` reserves a footprint from its `variant` alone — `header` is a
  full-width 200pt band, the other variants are fixed squares — and draws the
  image inside it. A component never reports a width larger than the space it
  was offered, so an agent cannot stretch the host's layout.
* Renderer state must be used from the main thread. The built-in transport
  delivers agent messages there for you.

## References

* [A2UI protocol v1.0](https://github.com/a2ui-project/a2ui/blob/main/specification/v1_0/docs/a2ui_protocol.md)
* [A2UI A2A extension v1.0](https://github.com/a2ui-project/a2ui/blob/main/specification/v1_0/extensions/a2a/docs/a2ui_extension_specification.md)
* [Basic catalog](https://github.com/a2ui-project/a2ui/blob/main/specification/v1_0/catalogs/basic/catalog.json)
* [A2A protocol](https://a2a-protocol.org)
