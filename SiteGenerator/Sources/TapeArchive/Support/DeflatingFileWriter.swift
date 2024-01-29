import struct Foundation.Date
import struct NIOCore.ByteBuffer
import struct NIOCore.ByteBufferAllocator

struct DeflatingFileWriter: ByteBufferConsumer {
  init(
    deflatedFileName: String?,
    deflatedFileModificationDate: Date?,
    byteBufferAllocator: ByteBufferAllocator,
    destination: some ByteBufferConsumer
  ) {
    self.outputBuffer =
      byteBufferAllocator
      .buffer(capacity: Self.defaultOutputBufferCapacity)
    self.destination = destination
    stream.setHeader(
      fileName: deflatedFileName,
      modificationDate: deflatedFileModificationDate)
  }

  mutating func consumeReadableBytes(of buffer: ByteBuffer) async throws {
    var mutableBuffer = buffer
    while mutableBuffer.readableBytes > 0 {
      try await writeWrittenOutput { [stream] outputBuffer in
        let outcome = stream.deflate(
          &mutableBuffer, into: &outputBuffer, flushBehavior: .flushWhenNeeded)
        precondition(outcome.bytesRead > 0 || outcome.bytesWritten > 0)
      }
    }
  }

  mutating func finishConsumingBytes() async throws {
    while true {
      let outcome = try await writeWrittenOutput { [stream] outputBuffer in
        stream.deflate(into: &outputBuffer, flushBehavior: .finish)
      }
      if outcome.isStreamEnd {
        break
      }
    }
  }

  private mutating func writeWrittenOutput<T>(
    _ writeToOutput: (inout ByteBuffer) throws -> T
  ) async throws -> T {
    /// output buffer must be cleared after use
    precondition(outputBuffer.writerIndex == 0)
    defer { outputBuffer.clear() }

    let result = try writeToOutput(&outputBuffer)

    try await destination.consumeReadableBytes(of: outputBuffer)

    return result
  }

  private let stream: DeflateStream = .init()
  private var outputBuffer: ByteBuffer
  private var destination: any ByteBufferConsumer

  private static let defaultOutputBufferCapacity = 128 /* kiB */ * 1024
}
