import struct NIOCore.ByteBuffer

extension DeflateStream {
  func deflate(
    _ inputBuffer: inout ByteBuffer,
    into outputBuffer: inout ByteBuffer,
    flushBehavior: FlushBehavior = .flushWhenNeeded
  ) -> DeflateOutcome {
    let outcome = inputBuffer.withUnsafeMutableReadableBytes { readableBytes in
      outputBuffer.withUnsafeMutableWritableBytes { writableBytes in
        deflate(readableBytes, into: writableBytes, flushBehavior: flushBehavior)
      }
    }
    inputBuffer.moveReaderIndex(forwardBy: outcome.bytesRead)
    outputBuffer.moveWriterIndex(forwardBy: outcome.bytesWritten)
    return outcome
  }
}
