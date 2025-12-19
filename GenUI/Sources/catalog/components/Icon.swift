//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import SwiftUI

private struct IconDataModel {
    let nameMap: JsonMap

    init(json: JsonMap) {
        self.nameMap = json["name"] as? JsonMap ?? [:]
    }

    var literalName: String? { nameMap["literalString"] as? String }
    var namePath: String? { nameMap["path"] as? String }
}

/// Supported icon names for the Icon component.
/// Maps A2UI icon names to SF Symbols.
public enum AvailableIcons: String, CaseIterable {
    case accountCircle
    case add
    case arrowBack
    case arrowForward
    case attachFile
    case calendarToday
    case call
    case camera
    case check
    case close
    case delete
    case download
    case edit
    case error
    case event
    case favorite
    case favoriteOff
    case folder
    case help
    case home
    case info
    case locationOn
    case lock
    case lockOpen
    case mail
    case menu
    case moreHoriz
    case moreVert
    case notifications
    case notificationsOff
    case payment
    case person
    case phone
    case photo
    case print
    case refresh
    case search
    case send
    case settings
    case share
    case shoppingCart
    case star
    case starHalf
    case starOff
    case upload
    case visibility
    case visibilityOff
    case warning

    public var systemName: String {
        switch self {
        case .accountCircle: return "person.crop.circle"
        case .add: return "plus"
        case .arrowBack: return "chevron.backward"
        case .arrowForward: return "chevron.forward"
        case .attachFile: return "paperclip"
        case .calendarToday: return "calendar"
        case .call: return "phone"
        case .camera: return "camera"
        case .check: return "checkmark"
        case .close: return "xmark"
        case .delete: return "trash"
        case .download: return "arrow.down.circle"
        case .edit: return "pencil"
        case .error: return "exclamationmark.triangle"
        case .event: return "calendar.badge.clock"
        case .favorite: return "heart.fill"
        case .favoriteOff: return "heart"
        case .folder: return "folder"
        case .help: return "questionmark.circle"
        case .home: return "house"
        case .info: return "info.circle"
        case .locationOn: return "location"
        case .lock: return "lock"
        case .lockOpen: return "lock.open"
        case .mail: return "envelope"
        case .menu: return "line.3.horizontal"
        case .moreHoriz: return "ellipsis"
        case .moreVert: return "ellipsis.vertical"
        case .notifications: return "bell"
        case .notificationsOff: return "bell.slash"
        case .payment: return "creditcard"
        case .person: return "person"
        case .phone: return "phone"
        case .photo: return "photo"
        case .print: return "printer"
        case .refresh: return "arrow.clockwise"
        case .search: return "magnifyingglass"
        case .send: return "paperplane"
        case .settings: return "gearshape"
        case .share: return "square.and.arrow.up"
        case .shoppingCart: return "cart"
        case .star: return "star.fill"
        case .starHalf: return "star.leadinghalf.filled"
        case .starOff: return "star"
        case .upload: return "arrow.up.circle"
        case .visibility: return "eye"
        case .visibilityOff: return "eye.slash"
        case .warning: return "exclamationmark.triangle"
        }
    }

    public static var allAvailable: [String] {
        allCases.map { $0.rawValue }
    }

    /// Resolves an icon by its A2UI name.
    /// Returns nil if the name is not supported.
    public static func fromName(_ name: String) -> AvailableIcons? {
        allCases.first { $0.rawValue == name }
    }
}

public let icon = CatalogItem(
    name: "Icon",
    dataSchema: S.object(
        properties: [
            "name": A2uiSchemas.stringReference(
                description: "The name of the icon to display. This can be a literal string ('literalString') or a reference to a value in the data model ('path', e.g. '/icon/name').",
                enumValues: AvailableIcons.allAvailable
            )
        ],
        required: ["name"]
    ),
    widgetBuilder: { itemContext in
        let data = IconDataModel(json: itemContext.data as? JsonMap ?? [:])

        if let literalName = data.literalName {
            let iconName = AvailableIcons.fromName(literalName)?.systemName ?? "questionmark"
            return AnyView(Image(systemName: iconName))
        }

        guard let namePath = data.namePath else {
            return AnyView(Image(systemName: "questionmark"))
        }

        let notifier: ValueNotifier<String?> = itemContext.dataContext.subscribe(DataPath(namePath))
        return AnyView(OptionalValueBuilder(listenable: notifier) { name in
            let iconName = AvailableIcons.fromName(name)?.systemName ?? "questionmark"
            return Image(systemName: iconName)
        })
    },
    exampleData: [
        {
            """
            [
              {
                "id": "root",
                "component": {
                  "Icon": {
                    "name": {
                      "literalString": "add"
                    }
                  }
                }
              }
            ]
            """
        }
    ]
)
