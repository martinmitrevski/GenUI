//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import SwiftUI
import Testing
@testable import GenUI

struct CatalogTests {
    @Test func catalogBuildsWidget() {
        let item = CatalogItem(
            name: "Text",
            dataSchema: S.object(),
            widgetBuilder: { _ in AnyView(Text("Hello")) }
        )
        let catalog = Catalog([item], catalogId: "catalog")
        let context = CatalogItemContext(
            data: ["Text": [:]],
            id: "root",
            buildChild: { _, _ in AnyView(EmptyView()) },
            dispatchEvent: { _ in },
            buildContext: GenUiBuildContext(),
            dataContext: DataContext(DataModel(), "/"),
            getComponent: { _ in nil },
            surfaceId: "surface"
        )

        _ = catalog.buildWidget(context)
        #expect(catalog.catalogId == "catalog")
    }

    @Test func catalogDefinitionIncludesComponents() {
        let item = CatalogItem(
            name: "Text",
            dataSchema: S.object(),
            widgetBuilder: { _ in AnyView(EmptyView()) }
        )
        let catalog = Catalog([item])
        let definition = catalog.definition as? ObjectSchema
        let components = definition?.properties["components"] as? ObjectSchema

        #expect(components?.properties["Text"] != nil)
    }
}
