//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import GenUI
import SwiftUI

/// The sample app's only screen: a prompt field plus the agent's surfaces.
struct ContentView: View {
    @StateObject private var viewModel = RestaurantSampleViewModel()

    var body: some View {
        ZStack {
            background
            ScrollView {
                VStack(spacing: 20) {
                    header
                    promptForm
                    examples
                    status
                    responses
                    surfaces
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 28)
            }
        }
        .task {
            await viewModel.connect()
        }
        .onDisappear {
            viewModel.dispose()
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [Color(red: 0.96, green: 0.97, blue: 1.0), Color(red: 0.99, green: 0.95, blue: 0.93)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color(red: 0.86, green: 0.35, blue: 0.3))
            Text(viewModel.title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text(connectionSubtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var connectionSubtitle: String {
        if let agentName = viewModel.agentName {
            return "Connected to \(agentName) · \(viewModel.serverUrlString)"
        }
        return "Connecting to \(viewModel.serverUrlString)"
    }

    private var promptForm: some View {
        HStack(spacing: 10) {
            TextField("What are you in the mood for?", text: $viewModel.inputText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.9))
                .clipShape(Capsule())
                .submitLabel(.send)
                .onSubmit {
                    Task { await viewModel.sendPrompt() }
                }

            Button {
                Task { await viewModel.sendPrompt() }
            } label: {
                Image(systemName: "paperplane.fill")
                    .padding(14)
                    .background(Color(red: 0.86, green: 0.35, blue: 0.3))
                    .foregroundStyle(.white)
                    .clipShape(Circle())
            }
            .disabled(viewModel.isProcessing || viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(viewModel.isProcessing ? 0.6 : 1)
        }
    }

    private var examples: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.examplePrompts, id: \.self) { prompt in
                    Button {
                        Task { await viewModel.send(prompt) }
                    } label: {
                        Text(prompt)
                            .font(.footnote)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.85))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        if viewModel.isProcessing {
            HStack(spacing: 8) {
                ProgressView()
                Text("Asking the agent...")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var responses: some View {
        if let last = viewModel.textResponses.last, !last.isEmpty {
            Text(last)
                .font(.subheadline)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var surfaces: some View {
        VStack(spacing: 16) {
            ForEach(viewModel.surfaceIds, id: \.self) { surfaceId in
                GenUiSurface(host: viewModel.conversation.host, surfaceId: surfaceId) {
                    AnyView(ProgressView().frame(maxWidth: .infinity))
                }
                .padding(16)
                .background(Color.white.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
            }
        }
    }
}

#Preview {
    ContentView()
}
