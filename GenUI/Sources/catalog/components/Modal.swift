//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import SwiftUI

private struct ModalData {
    let entryPointChild: String
    let contentChild: String

    init(json: JsonMap) {
        self.entryPointChild = json["entryPointChild"] as? String ?? ""
        self.contentChild = json["contentChild"] as? String ?? ""
    }
}

public let modal = CatalogItem(
    name: "Modal",
    dataSchema: S.object(
        properties: [
            "entryPointChild": A2uiSchemas.componentReference(description: "The widget that opens the modal."),
            "contentChild": A2uiSchemas.componentReference(description: "The widget to display in the modal.")
        ],
        required: ["entryPointChild", "contentChild"]
    ),
    widgetBuilder: { itemContext in
        let data = ModalData(json: itemContext.data as? JsonMap ?? [:])
        return itemContext.buildChild(data.entryPointChild, nil)
    }
)
