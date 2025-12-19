//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Combine
import Testing
@testable import GenUI

final class TestContentGenerator: ContentGenerator {
    let a2uiSubject = PassthroughSubject<A2uiMessage, Never>()
    let textSubject = PassthroughSubject<String, Never>()
    let errorSubject = PassthroughSubject<ContentGeneratorError, Never>()
    let processing = ValueNotifier<Bool>(false)

    var a2uiMessageStream: AnyPublisher<A2uiMessage, Never> { a2uiSubject.eraseToAnyPublisher() }
    var textResponseStream: AnyPublisher<String, Never> { textSubject.eraseToAnyPublisher() }
    var errorStream: AnyPublisher<ContentGeneratorError, Never> { errorSubject.eraseToAnyPublisher() }
    var isProcessing: ValueNotifier<Bool> { processing }

    func sendRequest(_ message: ChatMessage, history: [ChatMessage]?, clientCapabilities: A2UiClientCapabilities?) async {
    }

    func dispose() {
    }
}

struct GenUiConversationTests {
    @Test func surfaceUpdatesAppendMessages() async {
        let generator = TestContentGenerator()
        let processor = A2uiMessageProcessor(catalogs: [Catalog([])])
        let conversation = GenUiConversation(contentGenerator: generator, a2uiMessageProcessor: processor)

        let component = Component(id: "root", componentProperties: ["Text": [:]])
        processor.handleMessage(SurfaceUpdate(surfaceId: "surface", components: [component]))
        processor.handleMessage(BeginRendering(surfaceId: "surface", root: "root"))

        #expect(conversation.conversation.value.count == 1)
        conversation.dispose()
    }
}
