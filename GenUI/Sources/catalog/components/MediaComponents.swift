//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import AVKit
import SwiftUI

/// The media components of the A2UI basic catalog.
public enum MediaComponents {
    /// All media components, in catalog order.
    public static var all: [ComponentDefinition] {
        [image, video, audioPlayer]
    }

    /// Displays a remote or bundled image.
    public static let image = ComponentDefinition(
        name: "Image",
        description: "Displays an image from a URL.",
        properties: [
            "url": JsonSchema.dynamicString(description: "The URL of the image to display."),
            "description": JsonSchema.dynamicString(description: "Accessibility text for the image."),
            "fit": JsonSchema.string(
                description: "Specifies how the image should be resized to fit its container.",
                enumValues: ["contain", "cover", "fill", "none", "scaleDown"],
                defaultValue: "fill"
            ),
            "variant": JsonSchema.string(
                description: "A hint for the image size and style.",
                enumValues: ["icon", "avatar", "smallFeature", "mediumFeature", "largeFeature", "header"],
                defaultValue: "mediumFeature"
            ),
            "weight": JsonSchema.weight()
        ],
        required: ["url"],
        examples: [
            """
            [
              {
                "id": "root",
                "component": "Image",
                "url": "https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=300",
                "variant": "mediumFeature",
                "fit": "cover"
            }
            ]
            """
        ]
    ) { context in
        AnyView(
            A2uiImageView(
                source: context.string("url", default: ""),
                accessibilityText: context.string("description"),
                fit: context.option("fit", default: "fill"),
                variant: context.option("variant", default: "mediumFeature")
            )
        )
    }

    /// Plays a remote video.
    public static let video = ComponentDefinition(
        name: "Video",
        description: "Displays a video from a URL.",
        properties: [
            "url": JsonSchema.dynamicString(description: "The URL of the video to display."),
            "posterUrl": JsonSchema.dynamicString(
                description: "The URL of the poster image to display before the video plays."
            ),
            "weight": JsonSchema.weight()
        ],
        required: ["url"],
        examples: [
            """
            [
              {"id": "root", "component": "Video", "url": "https://example.com/clip.mp4"}
            ]
            """
        ]
    ) { context in
        AnyView(
            A2uiMediaPlayerView(
                url: URL(string: context.string("url", default: "")),
                posterUrl: URL(string: context.string("posterUrl", default: "")),
                title: nil,
                isAudioOnly: false
            )
        )
    }

    /// Plays a remote audio file.
    public static let audioPlayer = ComponentDefinition(
        name: "AudioPlayer",
        description: "A player for audio content from a URL.",
        properties: [
            "url": JsonSchema.dynamicString(description: "The URL of the audio to be played."),
            "description": JsonSchema.dynamicString(
                description: "A description of the audio, such as a title or summary."
            ),
            "weight": JsonSchema.weight()
        ],
        required: ["url"],
        examples: [
            """
            [
              {"id": "root", "component": "AudioPlayer", "url": "https://example.com/track.mp3", "description": "Sample track"}
            ]
            """
        ]
    ) { context in
        AnyView(
            A2uiMediaPlayerView(
                url: URL(string: context.string("url", default: "")),
                posterUrl: nil,
                title: context.string("description"),
                isAudioOnly: true
            )
        )
    }
}

/// Renders an A2UI `Image`, honouring its size and fit hints.
///
/// The image is drawn as an overlay of a sized box rather than sized directly.
/// A resizable image with `aspectRatio(.fill)` reports an intrinsic width
/// derived from its height, which would make a header image wider than its
/// container and stretch the whole surface; an overlay cannot affect the
/// layout of the box it fills.
private struct A2uiImageView: View {
    let source: String
    let accessibilityText: String?
    let fit: String
    let variant: String

    var body: some View {
        box
            .overlay(content)
            .clipped()
            .clipShape(shape)
            .accessibilityLabel(Text(accessibilityText ?? ""))
            .accessibilityHidden(accessibilityText == nil)
    }

    /// The layout footprint of the image, which never depends on the image itself.
    private var box: some View {
        Color.gray
            .opacity(0.12)
            .frame(width: layout.width, height: layout.height)
            .frame(maxWidth: layout.expandsHorizontally ? .infinity : nil)
    }

    private var layout: A2uiImageLayout {
        A2uiImageLayout(variant: variant)
    }

    @ViewBuilder
    private var content: some View {
        if source.isEmpty {
            EmptyView()
        } else if let url = URL(string: source), url.scheme != nil {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    scaled(image)
                case .failure:
                    EmptyView()
                default:
                    ProgressView()
                }
            }
        } else {
            // Names without a scheme are resolved from the app's asset catalog.
            scaled(Image(source))
        }
    }

    @ViewBuilder
    private func scaled(_ image: Image) -> some View {
        switch fit {
        case "none":
            image
        case "contain", "scaleDown":
            image.resizable().aspectRatio(contentMode: .fit)
        default:
            image.resizable().aspectRatio(contentMode: .fill)
        }
    }

    private var shape: AnyShape2 {
        variant == "avatar" ? AnyShape2(Circle()) : AnyShape2(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// The layout footprint the renderer gives an `Image` for a size variant.
///
/// The footprint deliberately never depends on the loaded image: a resizable
/// image with `aspectRatio(.fill)` derives its intrinsic width from its height,
/// which would let a header image push its surface wider than the screen.
struct A2uiImageLayout: Equatable {
    /// The fixed width, or `nil` when the image spans its container.
    let width: CGFloat?

    /// The fixed height of the image box.
    let height: CGFloat?

    /// Whether the box grows to fill the available width.
    let expandsHorizontally: Bool

    /// The height of a full-width header band.
    static let headerHeight: CGFloat = 200

    /// Resolves the footprint of an image variant.
    /// Unknown variants fall back to the catalog default, `mediumFeature`.
    init(variant: String) {
        switch variant {
        case "header":
            width = nil
            height = Self.headerHeight
            expandsHorizontally = true
        case "icon":
            width = 24
            height = 24
            expandsHorizontally = false
        case "avatar":
            width = 48
            height = 48
            expandsHorizontally = false
        case "smallFeature":
            width = 72
            height = 72
            expandsHorizontally = false
        case "largeFeature":
            width = 240
            height = 240
            expandsHorizontally = false
        default:
            width = 160
            height = 160
            expandsHorizontally = false
        }
    }
}

/// A type-erased shape, so image clipping can vary by variant on iOS 15.
private struct AnyShape2: Shape {
    private let pathBuilder: @Sendable (CGRect) -> Path

    init<S: Shape>(_ shape: S) {
        pathBuilder = { rect in shape.path(in: rect) }
    }

    func path(in rect: CGRect) -> Path {
        pathBuilder(rect)
    }
}

/// Plays audio or video using AVKit, with a poster and title fallback.
private struct A2uiMediaPlayerView: View {
    let url: URL?
    let posterUrl: URL?
    let title: String?
    let isAudioOnly: Bool

    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                #if os(iOS) || os(tvOS) || os(macOS)
                VideoPlayer(player: player)
                    .frame(height: isAudioOnly ? 80 : 200)
                #else
                unavailable
                #endif
            } else {
                unavailable
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let title, isAudioOnly {
                Text(title)
                    .font(.caption)
                    .padding(6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onAppear {
            guard player == nil, let url, url.scheme != nil else { return }
            player = AVPlayer(url: url)
        }
        .onDisappear {
            player?.pause()
        }
    }

    private var unavailable: some View {
        ZStack {
            Rectangle().fill(Color.gray.opacity(0.15))
            Image(systemName: isAudioOnly ? "speaker.wave.2" : "play.rectangle")
                .foregroundColor(.secondary)
        }
        .frame(height: isAudioOnly ? 80 : 200)
    }
}
