//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import SwiftUI
import UIKit

private struct TextFieldData {
    let text: JsonMap?
    let label: JsonMap?
    let textFieldType: String?
    let validationRegexp: String?
    let onSubmittedAction: JsonMap?

    init(json: JsonMap) {
        self.text = json["text"] as? JsonMap
        self.label = json["label"] as? JsonMap
        self.textFieldType = json["textFieldType"] as? String
        self.validationRegexp = json["validationRegexp"] as? String
        self.onSubmittedAction = json["onSubmittedAction"] as? JsonMap
    }
}

private struct BoundTextField: View {
    let text: Binding<String>
    let label: String?
    let textFieldType: String?
    let onSubmitted: (String) -> Void

    var body: some View {
        Group {
            if textFieldType == "obscured" {
                SecureField(label ?? "", text: text)
            } else {
                TextField(label ?? "", text: text)
            }
        }
        .textFieldStyle(.roundedBorder)
        .keyboardType(keyboardType)
        .onSubmit { onSubmitted(text.wrappedValue) }
    }

    private var keyboardType: UIKeyboardType {
        switch textFieldType {
        case "number": return .numberPad
        case "longText": return .default
        case "date": return .numbersAndPunctuation
        default: return .default
        }
    }
}

public let textField = CatalogItem(
    name: "TextField",
    dataSchema: S.object(
        description: "A text input field.",
        properties: [
            "text": A2uiSchemas.stringReference(description: "The initial value of the text field."),
            "label": A2uiSchemas.stringReference(),
            "textFieldType": S.string(enumValues: ["shortText", "longText", "number", "date", "obscured"]),
            "validationRegexp": S.string(),
            "onSubmittedAction": A2uiSchemas.action()
        ]
    ),
    widgetBuilder: { itemContext in
        let data = TextFieldData(json: itemContext.data as? JsonMap ?? [:])
        let valueRef = data.text
        let path = valueRef?["path"] as? String
        let notifier = itemContext.dataContext.subscribeToString(valueRef)
        let labelNotifier = itemContext.dataContext.subscribeToString(data.label)

        return AnyView(
            ValueObserverView(listenable: notifier) { currentValue in
                ValueObserverView(listenable: labelNotifier) { label in
                    let binding = Binding<String>(
                        get: { notifier.value ?? "" },
                        set: { newValue in
                            notifier.value = newValue
                            if let path {
                                itemContext.dataContext.update(DataPath(path), newValue)
                            }
                        }
                    )
                    return BoundTextField(
                        text: binding,
                        label: label,
                        textFieldType: data.textFieldType,
                        onSubmitted: { newValue in
                            guard let actionData = data.onSubmittedAction else { return }
                            let actionName = actionData["name"] as? String ?? ""
                            let contextDefinition = actionData["context"] as? [Any] ?? []
                            let resolvedContext = resolveContext(itemContext.dataContext, contextDefinition)
                            itemContext.dispatchEvent(
                                UserActionEvent(
                                    name: actionName,
                                    sourceComponentId: itemContext.id,
                                    context: resolvedContext
                                )
                            )
                        }
                    )
                }
            }
        )
    },
    exampleData: [
        {
            """
            [
              {
                "id": "root",
                "component": {
                  "TextField": {
                    "text": {
                      "literalString": "Hello World"
                    },
                    "label": {
                      "literalString": "Greeting"
                    }
                  }
                }
              }
            ]
            """
        }
    ]
)
