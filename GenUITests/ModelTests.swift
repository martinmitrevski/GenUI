//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Combine
import Testing
@testable import GenUI

struct DataPathTests {
    @Test func joinAndStartsWith() {
        let base = DataPath("/root/child")
        let relative = DataPath("grand")
        let joined = base.join(relative)

        #expect(joined.description == "/root/child/grand")
        #expect(joined.startsWith(DataPath("/root")))
        #expect(!joined.startsWith(DataPath("/other")))
    }

    @Test func basenameAndDirname() {
        let path = DataPath("/root/child")
        #expect(path.basename == "child")
        #expect(path.dirname.description == "/root")
    }
}

struct DataModelTests {
    @Test func updatesAndSubscriptions() {
        let model = DataModel()
        let notifier: ValueNotifier<String?> = model.subscribe(DataPath("/title"))

        #expect(notifier.value == nil)
        model.update(absolutePath: DataPath("/title"), contents: "Hello")
        #expect(notifier.value == "Hello")
    }

    @Test func rootUpdateWithList() {
        let model = DataModel()
        let contents: [Any] = [
            ["key": "name", "valueString": "Taylor"],
            ["key": "enabled", "valueBoolean": true]
        ]
        model.update(absolutePath: nil, contents: contents)

        #expect(model.snapshot["name"] as? String == "Taylor")
        #expect(model.snapshot["enabled"] as? Bool == true)
    }

    @Test func nestedUpdates() {
        let model = DataModel()
        model.update(absolutePath: DataPath("/items/0/title"), contents: "First")

        let value: String? = model.getValue(DataPath("/items/0/title"))
        #expect(value == "First")
    }
}

struct DataContextTests {
    @Test func resolvesAndUpdates() {
        let model = DataModel()
        let context = DataContext(model, "/root")
        context.update(DataPath("name"), "Value")

        let value: String? = model.getValue(DataPath("/root/name"))
        #expect(value == "Value")
    }
}

struct UiModelTests {
    @Test func componentEquality() {
        let compA = Component(id: "root", componentProperties: ["Text": ["value": "Hi"]])
        let compB = Component(id: "root", componentProperties: ["Text": ["value": "Hi"]])

        #expect(compA == compB)
        #expect(compA.type == "Text")
    }

    @Test func uiDefinitionCopyAndJson() {
        let component = Component(id: "root", componentProperties: ["Text": ["text": "Hello"]])
        let definition = UiDefinition(surfaceId: "surface", rootComponentId: "root", components: ["root": component])
        let updated = definition.copyWith(catalogId: "catalog")

        #expect(updated.catalogId == "catalog")
        let json = updated.toJson()
        #expect(json[surfaceIdKey] as? String == "surface")
        #expect((json["components"] as? JsonMap)?["root"] != nil)
    }
}

struct SchemaTests {
    @Test func schemaBuilders() {
        let schema = S.string(description: "value")
        #expect(schema is StringSchema)

        let objectSchema = S.object(properties: ["value": schema])
        #expect(objectSchema.properties["value"] is StringSchema)
    }

    @Test func a2uiSchemasSurfaceUpdate() {
        let catalog = Catalog([])
        let schema = A2uiSchemas.surfaceUpdateSchema(catalog: catalog)
        #expect(schema is ObjectSchema)
    }
}

struct LoggingTests {
    @Test func loggingCallback() {
        var captured: [String] = []
        let logger = configureGenUiLogging(level: .info) { _, message in
            captured.append(message)
        }

        logger.info("Hello")
        #expect(captured.contains { $0.contains("Hello") })
    }
}

struct WidgetUtilityTests {
    @Test func resolveContextUsesLiteral() {
        let model = DataModel()
        let context = DataContext(model, "/")
        let resolved = resolveContext(context, [
            ["key": "name", "value": ["literalString": "Taylor"]]
        ])

        #expect(resolved["name"] as? String == "Taylor")
    }
}
