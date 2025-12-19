//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import SwiftUI

private struct TabsData {
    let tabItems: [JsonMap]

    init(json: JsonMap) {
        self.tabItems = (json["tabItems"] as? [Any] ?? []).compactMap { $0 as? JsonMap }
    }
}

private struct TabsView: View {
    let tabItems: [JsonMap]
    let itemContext: CatalogItemContext
    @State private var selection: Int = 0

    var body: some View {
        TabView(selection: $selection) {
            ForEach(Array(tabItems.enumerated()), id: \.offset) { index, tabItem in
                let titleRef = tabItem["title"] as? JsonMap
                let childId = tabItem["child"] as? String ?? ""
                itemContext.buildChild(childId, nil)
                    .tag(index)
                    .tabItem {
                        if let titleRef {
                            OptionalValueBuilder(listenable: itemContext.dataContext.subscribeToString(titleRef)) { title in
                                Text(title)
                            }
                        } else {
                            Text("Tab")
                        }
                    }
            }
        }
    }
}

public let tabs = CatalogItem(
    name: "Tabs",
    dataSchema: S.object(
        properties: [
            "tabItems": S.list(
                items: S.object(
                    properties: [
                        "title": A2uiSchemas.stringReference(),
                        "child": A2uiSchemas.componentReference()
                    ],
                    required: ["title", "child"]
                )
            )
        ],
        required: ["tabItems"]
    ),
    widgetBuilder: { itemContext in
        let data = TabsData(json: itemContext.data as? JsonMap ?? [:])
        return AnyView(TabsView(tabItems: data.tabItems, itemContext: itemContext))
    }
)
