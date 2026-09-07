//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

import Foundation

/// Validates component nesting against catalog composition constraints.
///
/// Catalogs may declare `allowedParents` and `allowedChildren` on component
/// definitions. The renderer checks them while walking the tree and reports
/// `UNALLOWED_PARENT` or `UNALLOWED_CHILD` errors back to the agent, which is
/// how an agent learns that a generated layout is not renderable.
public enum CompositionValidator {
    /// Validates one parent-child relationship.
    ///
    /// Pass `nil` for `parent` when the component is the surface root; the
    /// reserved `Surface` container is then used as the parent type.
    /// - Returns: The error to report, or `nil` when the nesting is allowed.
    public static func validate(
        child: ComponentDefinition,
        childId: String,
        parent: ComponentDefinition?,
        surfaceId: String
    ) -> RendererError? {
        let parentType = parent?.name ?? A2uiProtocol.surfaceComponentType

        if let allowedParents = child.allowedParents, !allowedParents.contains(parentType) {
            return RendererError(
                code: RendererError.Code.unallowedParent,
                message: "Component '\(child.name)' cannot be placed inside '\(parentType)'. "
                    + "Allowed parents: \(allowedParents.joined(separator: ", ")).",
                surfaceId: surfaceId,
                path: "/components/\(childId)"
            )
        }

        if let parent, let allowedChildren = parent.allowedChildren, !allowedChildren.contains(child.name) {
            return RendererError(
                code: RendererError.Code.unallowedChild,
                message: "Component '\(parent.name)' does not allow '\(child.name)' children. "
                    + "Allowed children: \(allowedChildren.joined(separator: ", ")).",
                surfaceId: surfaceId,
                path: "/components/\(childId)"
            )
        }

        return nil
    }
}
