//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import SwiftUI

private struct ColumnData {
    let children: Any?
    let distribution: String?
    let alignment: String?

    init(json: JsonMap) {
        self.children = json["children"]
        self.distribution = json["distribution"] as? String
        self.alignment = json["alignment"] as? String
    }
}

private func parseColumnAlignment(_ alignment: String?) -> HorizontalAlignment {
    switch alignment {
    case "center": return .center
    case "end": return .trailing
    default: return .leading
    }
}

public let column = CatalogItem(
    name: "Column",
    dataSchema: S.object(
        properties: [
            "distribution": S.string(
                description: "How children are aligned on the main axis. ",
                enumValues: ["start", "center", "end", "spaceBetween", "spaceAround", "spaceEvenly"]
            ),
            "alignment": S.string(
                description: "How children are aligned on the cross axis. ",
                enumValues: ["start", "center", "end", "stretch", "baseline"]
            ),
            "children": A2uiSchemas.componentArrayReference(
                description: "Either an explicit list of widget IDs for the children, or a template with a data binding to the list of children."
            )
        ]
    ),
    widgetBuilder: { itemContext in
        let data = ColumnData(json: itemContext.data as? JsonMap ?? [:])

        return AnyView(ComponentChildrenBuilder(
            childrenData: data.children,
            dataContext: itemContext.dataContext,
            buildChild: itemContext.buildChild,
            getComponent: itemContext.getComponent,
            explicitListBuilder: { childIds, buildChild, getComponent, dataContext in
                AnyView(
                    VStack(alignment: parseColumnAlignment(data.alignment), spacing: 8) {
                        ForEach(childIds, id: \.self) { componentId in
                            buildWeightedChild(
                                componentId: componentId,
                                dataContext: dataContext,
                                buildChild: buildChild,
                                weight: getComponent(componentId)?.weight
                            )
                        }
                    }
                )
            },
            templateListWidgetBuilder: { list, componentId, dataBinding in
                let items = list.values.map { $0 }
                return AnyView(
                    VStack(alignment: parseColumnAlignment(data.alignment), spacing: 8) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, _ in
                            buildWeightedChild(
                                componentId: componentId,
                                dataContext: itemContext.dataContext.nested(DataPath("\(dataBinding)/\(index)")),
                                buildChild: itemContext.buildChild,
                                weight: itemContext.getComponent(componentId)?.weight
                            )
                        }
                    }
                )
            }
        ))
    }
)
