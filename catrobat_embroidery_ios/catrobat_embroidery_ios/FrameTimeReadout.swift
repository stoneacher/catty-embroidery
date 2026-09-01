#if DEBUG
import SwiftUI

/// US-309's readout: start a capture, stop it, read the four numbers off the screen.
///
/// **On screen rather than in a log, because the measurement happens on a device.** A capture
/// taken on a phone has to be readable without a console attached, and a screenshot of this
/// row is the artefact that goes into the thesis beside the frame it describes. The numbers
/// are shown only after `stop()`, so what is read is a settled result rather than four values
/// moving while they are being read.
///
/// Shown only for `SampleID.us309Synthetic`, so no shipping design's screenshot acquires a
/// diagnostic overlay it did not have before this story.
struct FrameTimeReadout: View {
    @State private var recorder = FrameTimeRecorder()

    var body: some View {
        HStack(spacing: 8) {
            Button(recorder.isRecording ? "Stop" : "Record") {
                if recorder.isRecording {
                    recorder.stop()
                } else {
                    recorder.start()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)

            Text(caption)
                // Monospaced digits so the row does not reflow while a capture runs, which
                // would make it unreadable at exactly the moment it is being watched.
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .padding(.bottom, 8)
        // Not an accessibility element worth describing: it is a developer instrument that
        // does not exist in any build a user can install, and giving it a label would put it
        // into the VoiceOver order of the stage this story is also screenshotting.
        .accessibilityHidden(true)
    }

    private var caption: String {
        if recorder.isRecording {
            let seconds = Double(recorder.frameCount) / 60
            return "capturing \(recorder.frameCount) frames (\(String(format: "%.1f", seconds)) s)"
        }
        guard let stats = recorder.statistics else {
            return "US-309 frame times"
        }
        return """
        n=\(stats.frameCount) med \(ms(stats.median)) p95 \(ms(stats.p95)) \
        p99 \(ms(stats.p99)) max \(ms(stats.worst)) · \
        \(stats.meetsSixtyFps ? "PASS" : "FAIL")\(stats.isLongEnoughToQuote ? "" : " (short)")
        """
    }

    private func ms(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
#endif
