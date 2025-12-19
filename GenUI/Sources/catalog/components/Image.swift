//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import SwiftUI

private struct ImageDataModel {
    let url: JsonMap
    let fit: String?
    let usageHint: String?

    init(json: JsonMap) {
        self.url = json["url"] as? JsonMap ?? [:]
        self.fit = json["fit"] as? String
        self.usageHint = json["usageHint"] as? String
    }
}

private func imageSchema(enableUsageHint: Bool) -> Schema {
    var properties: [String: Schema] = [
        "url": A2uiSchemas.stringReference(description: "Asset path (e.g. assets/...) or network URL (e.g. https://...)") ,
        "fit": S.string(
            description: "How the image should be inscribed into the box.",
            enumValues: ["fill", "fit", "center", "tile"]
        )
    ]
    if enableUsageHint {
        properties["usageHint"] = S.string(
            description: "A hint for the image size and style. One of: icon, avatar, smallFeature, mediumFeature, largeFeature, header.",
            enumValues: ["icon", "avatar", "smallFeature", "mediumFeature", "largeFeature", "header"]
        )
    }
    return S.object(properties: properties)
}

private func imageCatalogItem(enableUsageHint: Bool) -> CatalogItem {
    CatalogItem(
        name: "Image",
        dataSchema: imageSchema(enableUsageHint: enableUsageHint),
        widgetBuilder: { itemContext in
            let data = ImageDataModel(json: itemContext.data as? JsonMap ?? [:])
            let notifier = itemContext.dataContext.subscribeToString(data.url)

            return AnyView(OptionalValueBuilder(listenable: notifier) { location in
                if location.isEmpty {
                    genUiLogger.warning("Image widget created with no URL at path: \(itemContext.dataContext.path)")
                    return AnyView(EmptyView())
                }

                let contentMode: ContentMode = data.fit == "fill" ? .fill : .fit
                let imageView: AnyView

                if location.hasPrefix("assets/") {
                    imageView = AnyView(Image(location.replacingOccurrences(of: "assets/", with: ""))
                        .resizable()
                        .aspectRatio(contentMode: contentMode))
                } else if let url = URL(string: location) {
                    imageView = AnyView(AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: contentMode)
                    } placeholder: {
                        Color.gray.opacity(0.1)
                    })
                } else {
                    imageView = AnyView(Color.gray.opacity(0.1))
                }

                if data.usageHint == "avatar" {
                    return AnyView(imageView
                        .clipShape(Circle())
                        .frame(width: 48, height: 48))
                }

                if data.usageHint == "header" {
                    return AnyView(imageView.frame(maxWidth: .infinity))
                }

                let size: CGFloat
                switch data.usageHint {
                case "icon", "avatar": size = 32
                case "smallFeature": size = 50
                case "mediumFeature": size = 150
                case "largeFeature": size = 400
                default: size = 150
                }

                return AnyView(imageView.frame(width: size, height: size))
            })
        },
        exampleData: [
            {
                """
                [
                  {
                    "id": "root",
                    "component": {
                      "Image": {
                        "url": {
                          "literalString": "https://storage.googleapis.com/cms-storage-bucket/lockup_flutter_horizontal.c823e53b3a1a7b0d36a9.png"
                        },
                        "usageHint": "mediumFeature"
                      }
                    }
                  }
                ]
                """
            }
        ]
    )
}

public let image = imageCatalogItem(enableUsageHint: true)
public let imageFixedSize = imageCatalogItem(enableUsageHint: false)
