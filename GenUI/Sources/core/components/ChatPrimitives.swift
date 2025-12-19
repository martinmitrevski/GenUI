//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import SwiftUI

/// SwiftUI view for internal chat messages.
/// Displays a centered, muted system card.
public struct InternalMessageWidget: View {
    public let content: String

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(content: String) {
        self.content = content
    }

    public var body: some View {
        HStack {
            Spacer()
            Text("Internal message: \(content)")
                .padding(8)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
            Spacer()
        }
    }
}

/// SwiftUI view for a chat bubble row.
/// Aligns text and icon based on message side.
public struct ChatMessageWidget: View {
    public let text: String
    public let icon: String
    public let alignment: HorizontalAlignment

    /// Creates a new instance.
    /// Configures the instance with the provided parameters.
    public init(text: String, icon: String, alignment: HorizontalAlignment) {
        self.text = text
        self.icon = icon
        self.alignment = alignment
    }

    public var body: some View {
        HStack {
            if alignment == .leading {
                Image(systemName: icon)
                Text(text)
                    .padding(12)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(16)
                Spacer()
            } else {
                Spacer()
                Text(text)
                    .padding(12)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(16)
                Image(systemName: icon)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }
}
