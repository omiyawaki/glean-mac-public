import AppKit
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

enum ProbeFailure: Error, CustomStringConvertible {
    case cannotCreatePDF
    case cannotLoadPDF
    case cannotReadPage
    case unexpectedPageClass(String)
    case cannotCreateBitmapContext
    case missingPixelData
    case backgroundTooDark(CGFloat)
    case backgroundTooLight(CGFloat)
    case paletteBackgroundMismatch(actual: CGFloat, expected: CGFloat)
    case paletteFillMismatch(actual: CGFloat, expected: CGFloat)
    case textTooDark(CGFloat)

    var description: String {
        switch self {
        case .cannotCreatePDF:
            "Could not create fixture PDF."
        case .cannotLoadPDF:
            "Could not load fixture PDF."
        case .cannotReadPage:
            "Could not read first PDF page."
        case .unexpectedPageClass(let actual):
            "Dark-mode PDF load produced \(actual), not InvertedPDFPage."
        case .cannotCreateBitmapContext:
            "Could not create bitmap render context."
        case .missingPixelData:
            "Rendered bitmap had no readable pixel data."
        case .backgroundTooDark(let value):
            "Dark-mode PDF background is still too close to pure black: \(value)."
        case .backgroundTooLight(let value):
            "Dark-mode PDF background is too light to match macOS dark mode: \(value)."
        case .paletteBackgroundMismatch(let actual, let expected):
            "PDF dark-mode palette background \(actual) did not match native dark background \(expected)."
        case .paletteFillMismatch(let actual, let expected):
            "PDF dark-mode palette fill \(actual) did not invert to native dark background \(expected)."
        case .textTooDark(let value):
            "Dark-mode PDF text did not invert to a readable light value: \(value)."
        }
    }
}

@main
struct PDFDarkModeProbe {
    static func main() throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("glean-pdf-dark-mode-probe", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )

        let pdfURL = tempDirectory.appendingPathComponent("implicit-background-page.pdf")
        let imageURL = tempDirectory.appendingPathComponent("dark-render.png")
        try createFixturePDF(at: pdfURL)

        let loaded = try loadDarkModePage(from: pdfURL)
        let image = try render(page: loaded.page)
        try writePNG(image, to: imageURL)

        let background = try averageGray(in: image, rect: CGRect(x: 120, y: 120, width: 40, height: 40))
        let text = try averageGray(in: image, rect: CGRect(x: 60, y: 58, width: 80, height: 28))

        let targetBackground = nativeDarkDocumentBackgroundGray()
        try assertPaletteMatchesNativeDarkBackground(targetBackground)

        // Match the native macOS dark document surface instead of using full
        // inversion black or a near-black custom constant. Allow a little
        // rendering variance, but keep the page visibly off pure black.
        guard background >= targetBackground - 0.012 else {
            throw ProbeFailure.backgroundTooDark(background)
        }
        guard background <= targetBackground + 0.030 else {
            throw ProbeFailure.backgroundTooLight(background)
        }
        guard text > 0.70 else {
            throw ProbeFailure.textTooDark(text)
        }

        print("PDF dark-mode probe passed.")
        print(String(format: "target background gray: %.4f", targetBackground))
        print(String(format: "background gray: %.4f", background))
        print(String(format: "text gray: %.4f", text))
        print("render: \(imageURL.path)")
    }

    private struct LoadedPDFPage {
        let document: PDFDocument
        let page: PDFPage
    }

    private static func loadDarkModePage(from url: URL) throws -> LoadedPDFPage {
        let coordinator = PDFViewer.Coordinator()
        coordinator.darkMode = true

        guard let document = PDFDocument(url: url) else {
            throw ProbeFailure.cannotLoadPDF
        }
        document.delegate = coordinator

        guard let page = document.page(at: 0) else {
            throw ProbeFailure.cannotReadPage
        }
        guard page is InvertedPDFPage else {
            throw ProbeFailure.unexpectedPageClass(String(describing: type(of: page)))
        }
        return LoadedPDFPage(document: document, page: page)
    }

    private static func createFixturePDF(at url: URL) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 240, height: 240)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw ProbeFailure.cannotCreatePDF
        }

        context.beginPDFPage(nil)
        // Many publisher PDFs leave the page background implicit instead of
        // painting a white rectangle. That is the case that used to fall back
        // to PDFKit's black page background in dark mode.
        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x: 56, y: 56, width: 88, height: 32))
        context.endPDFPage()
        context.closePDF()
    }

    private static func render(page: PDFPage) throws -> CGImage {
        let width = 240
        let height = 240
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ProbeFailure.cannotCreateBitmapContext
        }

        context.setFillColor(NSColor.clear.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        page.draw(with: .mediaBox, to: context)

        guard let image = context.makeImage() else {
            throw ProbeFailure.missingPixelData
        }
        return image
    }

    private static func averageGray(in image: CGImage, rect: CGRect) throws -> CGFloat {
        let width = Int(rect.width)
        let height = Int(rect.height)
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ProbeFailure.cannotCreateBitmapContext
        }

        context.draw(image, in: CGRect(
            x: -rect.origin.x,
            y: -rect.origin.y,
            width: CGFloat(image.width),
            height: CGFloat(image.height)
        ))

        var total: CGFloat = 0
        var count: CGFloat = 0
        var offset = 0
        while offset < pixels.count {
            let red = CGFloat(pixels[offset]) / 255.0
            let green = CGFloat(pixels[offset + 1]) / 255.0
            let blue = CGFloat(pixels[offset + 2]) / 255.0
            total += (red + green + blue) / 3.0
            count += 1
            offset += bytesPerPixel
        }
        return total / count
    }

    private static func nativeDarkDocumentBackgroundGray() -> CGFloat {
        let appearance = NSAppearance(named: .darkAqua)!
        var gray: CGFloat = 0
        appearance.performAsCurrentDrawingAppearance {
            let color = NSColor.textBackgroundColor
                .usingColorSpace(NSColorSpace.deviceRGB)!
            gray = (color.redComponent + color.greenComponent + color.blueComponent) / 3.0
        }
        return gray
    }

    private static func assertPaletteMatchesNativeDarkBackground(_ target: CGFloat) throws {
        let background = try averageGray(PDFDarkModePalette.pageBackgroundColor)
        guard abs(background - target) <= 0.001 else {
            throw ProbeFailure.paletteBackgroundMismatch(actual: background, expected: target)
        }

        let fill = try averageGray(PDFDarkModePalette.inversionFillColor)
        let expectedFill = 1.0 - target
        guard abs(fill - expectedFill) <= 0.001 else {
            throw ProbeFailure.paletteFillMismatch(actual: fill, expected: expectedFill)
        }
    }

    private static func averageGray(_ color: NSColor) throws -> CGFloat {
        guard let rgb = color.usingColorSpace(NSColorSpace.deviceRGB) else {
            throw ProbeFailure.missingPixelData
        }
        return (rgb.redComponent + rgb.greenComponent + rgb.blueComponent) / 3.0
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return
        }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}
