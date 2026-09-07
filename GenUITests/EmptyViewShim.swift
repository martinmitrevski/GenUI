//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import SwiftUI

/// A stand-in view for catalog definitions in tests that never render.
struct EmptyViewShim: View {
    var body: some View {
        EmptyView()
    }
}
