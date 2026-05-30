import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct IconInput {
    let source: URL
    let masterOutput: URL
    let cropRect: CGRect
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let arguments = CommandLine.arguments

guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("Usage: swift scripts/generate_app_icons.swift <light-source.png> <dark-source.png>\n".utf8))
    exit(64)
}

let lightSource = URL(fileURLWithPath: arguments[1])
let darkSource = URL(fileURLWithPath: arguments[2])
let appIconSet = root.appendingPathComponent("SMCController/App/Assets.xcassets/AppIcon.appiconset")
let lightImageSet = root.appendingPathComponent("SMCController/App/Assets.xcassets/LightModeAppIcon.imageset")
let darkImageSet = root.appendingPathComponent("SMCController/App/Assets.xcassets/DarkModeAppIcon.imageset")

func cgImage(from url: URL) throws -> CGImage {
    guard
        let image = NSImage(contentsOf: url),
        let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else {
        throw NSError(domain: "IconGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to load image at \(url.path)"])
    }

    return cgImage
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "IconGenerator", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to create PNG destination at \(url.path)"])
    }

    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "IconGenerator", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to write PNG at \(url.path)"])
    }
}

func makeTransparentRoundedIcon(input: IconInput) throws {
    let sourceImage = try cgImage(from: input.source)
    guard let cropped = sourceImage.cropping(to: input.cropRect) else {
        throw NSError(domain: "IconGenerator", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unable to crop \(input.source.path)"])
    }

    let size = 1024
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "IconGenerator", code: 5, userInfo: [NSLocalizedDescriptionKey: "Unable to create output context"])
    }

    let visibleRect = CGRect(x: 62, y: 62, width: 900, height: 900)
    let cornerRadius: CGFloat = 188

    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    context.interpolationQuality = .high
    context.addPath(CGPath(roundedRect: visibleRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
    context.clip()
    context.draw(cropped, in: visibleRect)

    guard let output = context.makeImage() else {
        throw NSError(domain: "IconGenerator", code: 6, userInfo: [NSLocalizedDescriptionKey: "Unable to create output image"])
    }

    try writePNG(output, to: input.masterOutput)
}

try FileManager.default.createDirectory(at: lightImageSet, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: darkImageSet, withIntermediateDirectories: true)

let lightMaster = lightImageSet.appendingPathComponent("appicon-light-1024.png")
let darkMaster = darkImageSet.appendingPathComponent("appicon-dark-1024.png")

try makeTransparentRoundedIcon(input: IconInput(
    source: lightSource,
    masterOutput: lightMaster,
    cropRect: CGRect(x: 82, y: 72, width: 1100, height: 1100)
))
try makeTransparentRoundedIcon(input: IconInput(
    source: darkSource,
    masterOutput: darkMaster,
    cropRect: CGRect(x: 82, y: 72, width: 1100, height: 1100)
))

let sizes = [16, 32, 64, 128, 256, 512, 1024]
for size in sizes {
    let destination = appIconSet.appendingPathComponent("appicon-light-\(size).png")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    process.arguments = ["-z", "\(size)", "\(size)", lightMaster.path, "--out", destination.path]
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        throw NSError(domain: "IconGenerator", code: 7, userInfo: [NSLocalizedDescriptionKey: "sips failed for \(destination.path)"])
    }
}
