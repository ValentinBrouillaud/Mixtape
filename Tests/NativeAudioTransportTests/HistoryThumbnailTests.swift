import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import NativeAudioTransport

final class HistoryThumbnailTests: XCTestCase {
    func testLargeCoverBecomesSmallDecodableArtworkWithPreservedAspectRatio() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 1200, height: 600, bitsPerComponent: 8,
            bytesPerRow: 1200 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.3, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1200, height: 600))
        let image = try XCTUnwrap(context.makeImage())
        let original = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(original, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let result = try HistoryThumbnail.encode(original as Data)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(result as CFData, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertLessThanOrEqual(decoded.width, 256)
        XCTAssertLessThanOrEqual(decoded.height, 256)
        XCTAssertEqual(Double(decoded.width) / Double(decoded.height), 2, accuracy: 0.02)
        XCTAssertLessThan(result.count, HistoryThumbnail.maximumInputBytes)
    }

    func testRejectsNonImageAndExcessiveInput() {
        XCTAssertThrowsError(try HistoryThumbnail.encode(Data()))
        XCTAssertThrowsError(try HistoryThumbnail.encode(Data("<html>error</html>".utf8)))
        XCTAssertThrowsError(try HistoryThumbnail.encode(Data(repeating: 0, count: HistoryThumbnail.maximumInputBytes + 1)))
    }
}
