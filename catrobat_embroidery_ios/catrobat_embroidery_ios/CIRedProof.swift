import SwiftUI

// Deliberately broken, to prove the new CI job fails on an app-target compile
// error. Reverted in the next commit.
struct CIRedProof: View {
    var body: some View {
        let broken: Int = "this is not an Int"
        return Text(verbatim: "\(broken)")
    }
}
