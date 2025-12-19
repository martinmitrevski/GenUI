//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import SwiftUI

private struct DateTimeInputData {
    let value: JsonMap
    let enableDate: Bool
    let enableTime: Bool
    let outputFormat: String?

    init(json: JsonMap) {
        self.value = json["value"] as? JsonMap ?? [:]
        self.enableDate = json["enableDate"] as? Bool ?? true
        self.enableTime = json["enableTime"] as? Bool ?? true
        self.outputFormat = json["outputFormat"] as? String
    }
}

private struct DateTimePickerView: View {
    @State private var date: Date
    let enableDate: Bool
    let enableTime: Bool
    let outputFormat: String?
    let onChange: (String) -> Void

    init(
        initialValue: String?,
        enableDate: Bool,
        enableTime: Bool,
        outputFormat: String?,
        onChange: @escaping (String) -> Void
    ) {
        if let initialValue, let parsed = ISO8601DateFormatter().date(from: initialValue) {
            self._date = State(initialValue: parsed)
        } else {
            self._date = State(initialValue: Date())
        }
        self.enableDate = enableDate
        self.enableTime = enableTime
        self.outputFormat = outputFormat
        self.onChange = onChange
    }

    var body: some View {
        DatePicker(
            "Select a date/time",
            selection: $date,
            displayedComponents: components
        )
        .onChange(of: date) { newValue in
            onChange(format(date: newValue))
        }
    }

    private var components: DatePickerComponents {
        var components: DatePickerComponents = []
        if enableDate { components.insert(.date) }
        if enableTime { components.insert(.hourAndMinute) }
        return components
    }

    private func format(date: Date) -> String {
        if let outputFormat {
            let formatter = DateFormatter()
            formatter.dateFormat = outputFormat
            return formatter.string(from: date)
        }
        return ISO8601DateFormatter().string(from: date)
    }
}

public let dateTimeInput = CatalogItem(
    name: "DateTimeInput",
    dataSchema: S.object(
        properties: [
            "value": A2uiSchemas.stringReference(description: "The selected date and/or time."),
            "enableDate": S.boolean(),
            "enableTime": S.boolean(),
            "outputFormat": S.string()
        ],
        required: ["value"]
    ),
    widgetBuilder: { itemContext in
        let data = DateTimeInputData(json: itemContext.data as? JsonMap ?? [:])
        let notifier = itemContext.dataContext.subscribeToString(data.value)

        return AnyView(
            ValueObserverView(listenable: notifier) { currentValue in
                DateTimePickerView(
                    initialValue: currentValue,
                    enableDate: data.enableDate,
                    enableTime: data.enableTime,
                    outputFormat: data.outputFormat
                ) { formatted in
                    if let path = data.value["path"] as? String {
                        itemContext.dataContext.update(DataPath(path), formatted)
                        notifier.value = formatted
                    }
                }
            }
        )
    }
)
