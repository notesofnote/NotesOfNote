import NIOCore
import XCTest

@testable import TapeArchive

final class DeflateStreamTests: XCTestCase {
  func testDeflateAPI() {
    let stream: DeflateStream = .init()

    let inflatedString: StaticString = "Hello, World! Hello, World!"
    inflatedString.withUTF8Buffer { inputBytes in
      /// Perform a partial deflate
      do {
        let output = UnsafeMutableRawBufferPointer.allocate(
          byteCount: 18,
          alignment: MemoryLayout<UInt8>.alignment)
        defer { output.deallocate() }

        let timestamp = Date(timeIntervalSince1970: 42)
        let fileName = "Foo.txt"
        stream.setHeader(
          fileName: fileName,
          modificationDate: timestamp)

        let result = stream.deflate(
          UnsafeMutableRawBufferPointer(
            mutating: UnsafeRawBufferPointer(inputBytes)),
          into: output,
          flushBehavior: .finish)

        /// Check input was read
        XCTAssertEqual(result.bytesRead, inputBytes.count)

        /// Check header
        do {
          /// Magic number
          XCTAssertEqual(
            [0x1f, 0x8b],
            Array(output[0..<2]))
          /// Compression Method (Deflate)
          XCTAssertEqual(8, output[2])
          /// Flags (has file name)
          XCTAssertEqual(0b01000, output[3])
          /// Timestamp
          XCTAssertEqual(
            withUnsafeBytes(of: UInt32(timestamp.timeIntervalSince1970)) { Array($0) },
            Array(output[4..<8]))
          /// XFlags
          XCTAssertEqual(0, output[8])
          /// Skip OS
          // XCTAssertEqual(_, output[9])
          /// Filename
          XCTAssertEqual(
            fileName,
            output[10...]
              .firstIndex(of: 0)
              .map { endIndex in
                String(decoding: output[10..<endIndex], as: UTF8.self)
              }
          )
          XCTAssertFalse(result.isStreamEnd)
        }
      }

      /// Finish the deflate
      do {
        let output = UnsafeMutableRawBufferPointer.allocate(
          byteCount: 1024,
          alignment: MemoryLayout<UInt8>.alignment)
        defer { output.deallocate() }

        let result = stream.deflate(
          into: output,
          flushBehavior: .finish)

        /// Value determined experimentally
        XCTAssertEqual(result.bytesWritten, 27)

        XCTAssertTrue(result.isStreamEnd)
      }
    }
  }
}
