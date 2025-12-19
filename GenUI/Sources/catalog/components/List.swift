//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import SwiftUI

private struct ListData {
    let children: Any?
    let direction: String?
    let alignment: String?

    init(json: JsonMap) {
        self.children = json["children"]
        self.direction = json["direction"] as? String
        self.alignment = json["alignment"] as? String
    }
}

private func listAlignment(_ alignment: String?) -> HorizontalAlignment {
    switch alignment {
    case "center": return .center
    case "end": return .trailing
    default: return .leading
    }
}

public let list = CatalogItem(
    name: "List",
    dataSchema: S.object(
        properties: [
            "children": A2uiSchemas.componentArrayReference(),
            "direction": S.string(enumValues: ["vertical", "horizontal"]),
            "alignment": S.string(enumValues: ["start", "center", "end", "stretch"])
        ],
        required: ["children"]
    ),
    widgetBuilder: { itemContext in
        let data = ListData(json: itemContext.data as? JsonMap ?? [:])
        let isHorizontal = data.direction == "horizontal"

        return AnyView(ComponentChildrenBuilder(
            childrenData: data.children,
            dataContext: itemContext.dataContext,
            buildChild: itemContext.buildChild,
            getComponent: itemContext.getComponent,
            explicitListBuilder: { childIds, buildChild, _, dataContext in
                AnyView(
                    ScrollView(isHorizontal ? .horizontal : .vertical) {
                        if isHorizontal {
                            LazyHStack(alignment: .center, spacing: 8) {
                                ForEach(childIds, id: \.self) { id in
                                    buildChild(id, dataContext)
                                }
                            }
                        } else {
                            LazyVStack(alignment: listAlignment(data.alignment), spacing: 8) {
                                ForEach(childIds, id: \.self) { id in
                                    buildChild(id, dataContext)
                                }
                            }
                        }
                    }
                )
            },
            templateListWidgetBuilder: { list, componentId, dataBinding in
                let keys = list.keys.sorted()
                return AnyView(
                    ScrollView(isHorizontal ? .horizontal : .vertical) {
                        if isHorizontal {
                            LazyHStack(alignment: .center, spacing: 8) {
                                ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                                    let nestedContext = itemContext.dataContext.nested(DataPath("\(dataBinding)/\(key)"))
                                    itemContext.buildChild(componentId, nestedContext)
                                }
                            }
                        } else {
                            LazyVStack(alignment: listAlignment(data.alignment), spacing: 8) {
                                ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                                    let nestedContext = itemContext.dataContext.nested(DataPath("\(dataBinding)/\(key)"))
                                    itemContext.buildChild(componentId, nestedContext)
                                }
                            }
                        }
                    }
                )
            }
        ))
    }
)
