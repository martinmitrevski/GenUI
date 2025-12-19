//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation

/// Prompt snippets used to guide UI generation.
/// Includes reusable system guidance for A2UI tools.
public enum GenUiPromptFragments {
    public static let basicChat = """

# Outputting UI information

Use the provided tools to respond to the user using rich UI elements.

Important considerations:
- When you are asking for information from the user, you should always include
  at least one submit button of some kind or another submitting element so that
  the user can indicate that they are done providing information.
- After you have modified the UI, be sure to use the provideFinalOutput to give
  control back to the user so they can respond.
"""
}
