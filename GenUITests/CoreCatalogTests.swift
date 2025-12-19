//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Testing
@testable import GenUI

struct CoreCatalogTests {
    @Test func coreCatalogHasItems() {
        let catalog = CoreCatalogItems.asCatalog()
        #expect(catalog.catalogId == standardCatalogId)
        #expect(!catalog.items.isEmpty)
    }
}
