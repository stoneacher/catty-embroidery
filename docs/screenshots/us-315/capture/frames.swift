// Extracts every frame of a simulator recording as a PNG named by its timestamp.
//
//     swiftc -O frames.swift -o frames && ./frames <video.mp4> <outdir> [start] [end]
//
// `simctl io recordVideo` writes a frame only when the screen changes, so the timestamps alone
// locate a transition: a burst of closely spaced frames is an animation. AVFoundation rather
// than ffmpeg, so it needs nothing beyond Xcode.
import AppKit
import AVFoundation

let arguments = CommandLine.arguments
let video = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])
let start = arguments.count > 3 ? Double(arguments[3]) ?? 0 : 0
let end = arguments.count > 4 ? Double(arguments[4]) ?? .greatestFiniteMagnitude : .greatestFiniteMagnitude
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let asset = AVURLAsset(url: video)
guard let track = try await asset.loadTracks(withMediaType: .video).first else {
    fatalError("\(video.path) has no video track")
}

let reader = try AVAssetReader(asset: asset)
let trackOutput = AVAssetReaderTrackOutput(
    track: track,
    outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
)
reader.add(trackOutput)
reader.startReading()

var written = 0
while let sample = trackOutput.copyNextSampleBuffer() {
    let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
    guard time >= start else { continue }
    if time > end {
        break
    }
    guard let buffer = CMSampleBufferGetImageBuffer(sample),
          let cgImage = CIContext().createCGImage(
              CIImage(cvPixelBuffer: buffer),
              from: CGRect(
                  x: 0, y: 0,
                  width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer)
              )
          ),
          let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    else { continue }
    try png.write(to: output.appendingPathComponent(String(format: "f%04d_%.3f.png", written, time)))
    written += 1
}

print("wrote \(written) frames")
