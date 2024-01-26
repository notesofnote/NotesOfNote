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

    precondition(outcome.bytesRead <= inputBuffer.readableBytes)
    inputBuffer.moveReaderIndex(forwardBy: outcome.bytesRead)

    precondition(outcome.bytesWritten <= outputBuffer.writableBytes)
    outputBuffer.moveWriterIndex(forwardBy: outcome.bytesWritten)

    return outcome
  }
}
