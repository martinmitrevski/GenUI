//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation

/// Namespace for the default GenUI catalog items.
/// Exposes the standard catalog and item references.
public enum CoreCatalogItems {
    private static let audioPlayerItem = GenUI.audioPlayer
    private static let buttonItem = GenUI.button
    private static let cardItem = GenUI.card
    private static let checkBoxItem = GenUI.checkBox
    private static let columnItem = GenUI.column
    private static let dateTimeInputItem = GenUI.dateTimeInput
    private static let dividerItem = GenUI.divider
    private static let iconItem = GenUI.icon
    private static let imageItem = GenUI.image
    private static let imageFixedSizeItem = GenUI.imageFixedSize
    private static let listItem = GenUI.list
    private static let modalItem = GenUI.modal
    private static let multipleChoiceItem = GenUI.multipleChoice
    private static let rowItem = GenUI.row
    private static let sliderItem = GenUI.slider
    private static let tabsItem = GenUI.tabs
    private static let textItem = GenUI.text
    private static let textFieldItem = GenUI.textField
    private static let videoItem = GenUI.video

    public static let audioPlayer = audioPlayerItem
    public static let button = buttonItem
    public static let card = cardItem
    public static let checkBox = checkBoxItem
    public static let column = columnItem
    public static let dateTimeInput = dateTimeInputItem
    public static let divider = dividerItem
    public static let icon = iconItem
    public static let image = imageItem
    public static let imageFixedSize = imageFixedSizeItem
    public static let list = listItem
    public static let modal = modalItem
    public static let multipleChoice = multipleChoiceItem
    public static let row = rowItem
    public static let slider = sliderItem
    public static let tabs = tabsItem
    public static let text = textItem
    public static let textField = textFieldItem
    public static let video = videoItem

    /// Builds the standard catalog containing core components.
    /// Use this to register the default widget set.
    public static func asCatalog() -> Catalog {
        Catalog(
            [
                audioPlayerItem,
                buttonItem,
                cardItem,
                checkBoxItem,
                columnItem,
                dateTimeInputItem,
                dividerItem,
                iconItem,
                imageItem,
                listItem,
                modalItem,
                multipleChoiceItem,
                rowItem,
                sliderItem,
                tabsItem,
                textItem,
                textFieldItem,
                videoItem
            ],
            catalogId: standardCatalogId
        )
    }
}
