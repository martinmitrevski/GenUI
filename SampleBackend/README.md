# A2UI sample backend

A deterministic A2UI v1.0 agent that finds restaurants and takes an order, plus a
dependency-free A2A server that exposes it over HTTP. It exists so this
repository can be run end to end without an API key or an agent framework.

## Running

```bash
swift run a2ui-sample-server                       # http://localhost:10002
swift run a2ui-sample-server --port 8080 --host 192.168.1.20
```

Use `--host` when running the iOS app on a device, so the agent card advertises
an address the device can reach. The simulator can use `localhost`.

## Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/.well-known/agent-card.json` | The A2A agent card, advertising the A2UI extension and the catalogs the agent generates. |
| `POST` | `/` | JSON-RPC: `message/stream` (server-sent events) and `message/send` (single response). |
| `GET` | `/health` | Liveness probe. |

A2UI messages travel as an A2A `DataPart` whose `data` is an array of messages
and whose metadata sets `mimeType` to `application/a2ui+json`, as the A2A
extension requires.

## The conversation

1. **Any prompt** → `createSurface` with a `List` of restaurant cards built from
   one template component bound to `/restaurants`, plus a text summary.
2. **`selectRestaurant`** → the list surface is deleted and an order form is
   created with `sendDataModel: true`: a `ChoicePicker` for the dishes, pickup or
   delivery chips, a `DateTimeInput`, an address and notes field, and a primary
   button whose `checks` keep it disabled until the order is valid.
3. **`deliveryEstimate`** → the order form binds a text to a function the
   renderer does not know, so the renderer sends `callAgentFunction` and the
   agent answers with `agentFunctionResponse`.
4. **`placeOrder`** → the agent validates server side. Missing dishes or a
   delivery order without an address produce an `updateDataModel` that writes the
   message into the form; a valid order renders a confirmation whose line items
   repeat a template over `/confirmation/lines` — a dish photo, the numbered name
   from `@index`, and a price formatted by `formatCurrency` — followed by the
   totals.
5. **`startOver`** → back to step 1.

Every step deletes the previous surface, because A2UI surface ids must be unique
for the lifetime of a renderer.

## Layout

| Path | Contents |
| --- | --- |
| `Sources/A2uiSampleAgent/RestaurantAgent.swift` | The conversation state machine and the A2UI messages it emits. |
| `Sources/A2uiSampleAgent/A2AAgentService.swift` | The A2A binding: agent card, request decoding, response encoding. |
| `Sources/A2uiSampleAgent/A2uiBuilders.swift` | Small helpers for building components in Swift. |
| `Sources/A2uiSampleAgent/RestaurantData.swift` | The data model and the search used by the agent. |
| `Sources/A2uiSampleAgent/Resources/restaurants.json` | The sample data. Edit it to change the demo. |
| `Sources/A2uiSampleServer/` | The HTTP/1.1 server, request parsing and SSE encoding. |

The agent and the A2A binding contain no networking, so they are unit tested
directly, and the end-to-end tests drive the real client against them in process.

## Using a real model instead

The agent's `respond(to:)` is the only place that decides what to render. To
drive it with a language model, keep the same request and response types and
build the prompt with `A2uiPromptBuilder.systemPrompt(catalogs:)`, which embeds
the renderer's catalog document and the protocol rules the model needs.
