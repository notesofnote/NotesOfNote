import NIOCore
import XCTest

@testable import TapeArchive

final class DeflateStreamTests: XCTestCase {
  func testSimpleDeflate() {
    let stream: DeflateStream = .init()

    ("Hello, World! Hello, World!" as StaticString)
      .withUTF8Buffer { inputBytes in
        /// Perform a partial deflate
        do {
          let output = UnsafeMutableRawBufferPointer.allocate(
            byteCount: 10,
            alignment: MemoryLayout<UInt8>.alignment)
          defer { output.deallocate() }

          let result = stream.deflate(
            UnsafeMutableRawBufferPointer(
              mutating: UnsafeRawBufferPointer(inputBytes)),
            into: output,
            flushBehavior: .finish)

          /// Check input was read
          XCTAssertEqual(result.bytesRead, inputBytes.count)

          /// Check output
          XCTAssertEqual(
            [31, 139, 8, 0, 0, 0, 0, 0, 0, 19],
            Array(output[0..<result.bytesWritten]))
          XCTAssertFalse(result.isStreamEnd)
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

          XCTAssertEqual(result.bytesWritten, 27)
          XCTAssertTrue(result.isStreamEnd)
        }
      }
  }
}
