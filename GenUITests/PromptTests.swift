//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Testing
@testable import GenUI

struct PromptTests {
    @Test func promptIncludesMarker() {
        #expect(GenUiPromptFragments.basicChat.contains("Outputting UI information"))
    }
}
