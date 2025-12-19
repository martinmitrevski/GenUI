//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import SwiftUI
import GenUI

struct ContentView: View {
    @StateObject private var viewModel = RestaurantSampleViewModel()

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color(red: 0.95, green: 0.97, blue: 1.0), Color(red: 0.98, green: 0.94, blue: 0.93)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    header
                    promptForm
                    statusSection
                    responsesSection
                    surfacesSection
                }
                .padding(.vertical, 32)
                .padding(.horizontal, 20)
            }
        }
        .onDisappear {
            viewModel.dispose()
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color(red: 0.86, green: 0.35, blue: 0.3))
            Text(viewModel.title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.15, green: 0.2, blue: 0.3))
            Text("Connected to \(viewModel.serverUrlString)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(red: 0.4, green: 0.45, blue: 0.55))
        }
        .frame(maxWidth: .infinity)
    }

    private var promptForm: some View {
        VStack(spacing: 12) {
            TextField(viewModel.placeholder, text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color(red: 0.86, green: 0.35, blue: 0.3), lineWidth: 1)
                )
                .lineLimit(1...3)
                .submitLabel(.send)
                .onSubmit {
                    Task { await viewModel.sendPrompt() }
                }

            Button {
                Task { await viewModel.sendPrompt() }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isProcessing {
                        ProgressView()
                            .progressViewStyle(.circular)
                    }
                    Text(viewModel.isProcessing ? "Sending..." : "Send")
                        .font(.system(size: 16, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(red: 0.86, green: 0.35, blue: 0.3))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 24))
            }
            .disabled(viewModel.isProcessing || viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(viewModel.isProcessing ? 0.7 : 1.0)
        }
    }

    private var statusSection: some View {
        VStack(spacing: 8) {
            if viewModel.isProcessing {
                ProgressView()
                    .progressViewStyle(.circular)
                Text(viewModel.loadingText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(red: 0.3, green: 0.35, blue: 0.45))
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(red: 0.75, green: 0.2, blue: 0.2))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var responsesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let last = viewModel.textResponses.last, !last.isEmpty {
                Text("Agent Response")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.25, green: 0.3, blue: 0.4))
                Text(last)
                    .font(.system(size: 15))
                    .foregroundStyle(Color(red: 0.2, green: 0.25, blue: 0.35))
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var surfacesSection: some View {
        VStack(spacing: 20) {
            ForEach(viewModel.surfaceIds, id: \.self) { surfaceId in
                GenUiSurface(host: viewModel.conversation.host, surfaceId: surfaceId)
                    .padding(16)
                    .background(Color.white.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
