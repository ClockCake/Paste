import Foundation
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

enum ImageCoder {
    #if os(macOS)
    static func normalizedJPEGData(from pasteboard: NSPasteboard, maxDimension: CGFloat = 1920) -> Data? {
        guard let image = imageFromPasteboard(pasteboard) else {
            return nil
        }
        return jpegData(from: image, maxDimension: maxDimension, quality: 0.85)
    }
    #elseif os(iOS)
    static func normalizedJPEGData(from pasteboard: UIPasteboard, maxDimension: CGFloat = 1920) -> Data? {
        guard let image = pasteboard.image else {
            return nil
        }
        return jpegData(from: image, maxDimension: maxDimension, quality: 0.85)
    }
    #endif

    static func thumbnailJPEGData(from imageData: Data, maxDimension: CGFloat = 360) -> Data? {
        #if os(macOS)
        guard let image = NSImage(data: imageData) else {
            return nil
        }
        #elseif os(iOS)
        guard let image = UIImage(data: imageData) else {
            return nil
        }
        #endif
        return jpegData(from: image, maxDimension: maxDimension, quality: 0.72)
    }

    #if os(macOS)
    static func jpegData(from image: NSImage, maxDimension: CGFloat, quality: CGFloat) -> Data? {
        let outputImage = resizedImageIfNeeded(image, maxDimension: maxDimension)
        guard
            let tiffData = outputImage.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    private static func imageFromPasteboard(_ pasteboard: NSPasteboard) -> NSImage? {
        if
            let tiffData = pasteboard.data(forType: .tiff),
            let image = NSImage(data: tiffData)
        {
            return image
        }

        if
            let pngData = pasteboard.data(forType: .png),
            let image = NSImage(data: pngData)
        {
            return image
        }

        let classes: [AnyClass] = [NSImage.self]
        if
            let objects = pasteboard.readObjects(forClasses: classes, options: nil) as? [NSImage],
            let image = objects.first
        {
            return image
        }

        return nil
    }

    private static func resizedImageIfNeeded(_ image: NSImage, maxDimension: CGFloat) -> NSImage {
        let size = image.size
        let largestEdge = max(size.width, size.height)

        guard largestEdge > maxDimension, largestEdge > 0 else {
            return image
        }

        let ratio = maxDimension / largestEdge
        let newSize = NSSize(width: size.width * ratio, height: size.height * ratio)
        let outputImage = NSImage(size: newSize)

        outputImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize))
        outputImage.unlockFocus()

        return outputImage
    }
    #elseif os(iOS)
    static func jpegData(from image: UIImage, maxDimension: CGFloat, quality: CGFloat) -> Data? {
        let outputImage = resizedImageIfNeeded(image, maxDimension: maxDimension)
        return outputImage.jpegData(compressionQuality: quality)
    }

    private static func resizedImageIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let largestEdge = max(size.width, size.height)

        guard largestEdge > maxDimension, largestEdge > 0 else {
            return image
        }

        let ratio = maxDimension / largestEdge
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    #endif
}
