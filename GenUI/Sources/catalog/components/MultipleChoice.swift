//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import SwiftUI

private struct MultipleChoiceData {
    let selections: JsonMap
    let options: [JsonMap]
    let maxAllowedSelections: Int?

    init(json: JsonMap) {
        self.selections = json["selections"] as? JsonMap ?? [:]
        self.options = (json["options"] as? [Any] ?? []).compactMap { $0 as? JsonMap }
        self.maxAllowedSelections = (json["maxAllowedSelections"] as? NSNumber)?.intValue
    }
}

public let multipleChoice = CatalogItem(
    name: "MultipleChoice",
    dataSchema: S.object(
        properties: [
            "selections": A2uiSchemas.stringArrayReference(),
            "options": S.list(
                items: S.object(
                    properties: [
                        "label": A2uiSchemas.stringReference(),
                        "value": S.string()
                    ],
                    required: ["label", "value"]
                )
            ),
            "maxAllowedSelections": S.integer()
        ],
        required: ["selections", "options"]
    ),
    widgetBuilder: { itemContext in
        let data = MultipleChoiceData(json: itemContext.data as? JsonMap ?? [:])
        let selectionsNotifier = itemContext.dataContext.subscribeToObjectArray(data.selections)

        return AnyView(
            ValueObserverView(listenable: selectionsNotifier) { selections in
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(data.options.enumerated()), id: \.offset) { _, option in
                        let value = option["value"] as? String ?? ""
                        let labelRef = option["label"] as? JsonMap
                        if data.maxAllowedSelections == 1 {
                            Button(action: {
                                if let path = data.selections["path"] as? String {
                                    itemContext.dataContext.update(DataPath(path), [value])
                                }
                            }) {
                                HStack {
                                    if (selections ?? []).first as? String == value {
                                        Image(systemName: "largecircle.fill.circle")
                                    } else {
                                        Image(systemName: "circle")
                                    }
                                    if let labelRef {
                                        OptionalValueBuilder(listenable: itemContext.dataContext.subscribeToString(labelRef)) { label in
                                            Text(label)
                                        }
                                    } else {
                                        Text(value)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        } else {
                            let isSelected = (selections ?? []).contains { String(describing: $0) == value }
                            Toggle(isOn: Binding(
                                get: { isSelected },
                                set: { newValue in
                                    guard let path = data.selections["path"] as? String else { return }
                                    var newSelections = (selections ?? []).map { String(describing: $0) }
                                    if newValue {
                                        if data.maxAllowedSelections == nil || newSelections.count < (data.maxAllowedSelections ?? 0) {
                                            newSelections.append(value)
                                        }
                                    } else {
                                        newSelections.removeAll { $0 == value }
                                    }
                                    itemContext.dataContext.update(DataPath(path), newSelections)
                                }
                            )) {
                                if let labelRef {
                                    OptionalValueBuilder(listenable: itemContext.dataContext.subscribeToString(labelRef)) { label in
                                        Text(label)
                                    }
                                } else {
                                    Text(value)
                                }
                            }
                        }
                    }
                }
            }
        )
    }
)
