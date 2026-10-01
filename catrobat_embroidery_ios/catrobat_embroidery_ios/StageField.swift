import StagePreview
import SwiftUI

/// The hoop and the two fields. Signature-only stub for US-315's red phase.
enum StageField {
    struct Geometry: Equatable {
        let mat: CGRect
        let hoop: CGRect
        let outlineWidth: Double
    }

    static func geometry(
        transform _: StageTransform,
        size _: CGSize,
        increasedContrast _: Bool
    ) -> Geometry {
        Geometry(mat: .zero, hoop: .zero, outlineWidth: 0)
    }
}
