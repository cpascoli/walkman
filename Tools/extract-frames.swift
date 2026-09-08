import AVFoundation
import AppKit

// usage: extract <movie> <outDir> <fps> <speedup> <width>
let args = CommandLine.arguments
let asset = AVURLAsset(url: URL(fileURLWithPath: args[1]))
let outDir = args[2]
let fps = Double(args[3])!
let speedup = Double(args[4])!
let width = Int(args[5])!

let duration = try await asset.load(.duration).seconds
// One output frame every `step` seconds of source time.
let step = speedup / fps
let count = Int(duration / step)

let gen = AVAssetImageGenerator(asset: asset)
gen.appliesPreferredTrackTransform = true
gen.requestedTimeToleranceBefore = CMTime(seconds: 0.02, preferredTimescale: 600)
gen.requestedTimeToleranceAfter = CMTime(seconds: 0.02, preferredTimescale: 600)
gen.maximumSize = CGSize(width: width, height: 4000)

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

for i in 0..<count {
    let t = CMTime(seconds: Double(i) * step, preferredTimescale: 600)
    guard let cg = try? gen.copyCGImage(at: t, actualTime: nil) else { continue }
    let rep = NSBitmapImageRep(cgImage: cg)
    guard let png = rep.representation(using: .png, properties: [:]) else { continue }
    try png.write(to: URL(fileURLWithPath: String(format: "\(outDir)/f%04d.png", i)))
}
print("frames: \(count), source \(String(format: "%.1f", duration))s -> \(String(format: "%.1f", duration / speedup))s @ \(fps)fps")
