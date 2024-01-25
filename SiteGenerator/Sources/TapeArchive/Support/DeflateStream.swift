import CZlib

/// A type which deflates a stream of input data
final class DeflateStream {

  /// Creates a new `DeflateStream`
  init() {
    c = z_stream()

    let result = CZlib_deflateInit2(
      &c,
      /* compressionLevel: */ Z_DEFAULT_COMPRESSION,
      /* method: */ Z_DEFLATED,
      /* windowBits: */ 15 + 16,
      /* memLevel: */ 8,
      /* strategy: */ Z_DEFAULT_STRATEGY)
    guard result == Z_OK else {
      /// The only failures possible at this point are out-of-memory and stream misconfiguration.
      /// We can treat both as fatal errors to simplify the API
      fatalError()
    }
  }
  deinit {
    let result = deflateEnd(&c)
    switch result {
    case Z_OK:
      break
    case Z_DATA_ERROR:
      /// The stream was deallocated while there was pending data still in the stream.
      /// We consider this OK, but it may make sense to put a breakpoint here during debigging.
      break
    case Z_STREAM_ERROR:
      /// We don't expect the stream to be in an incosistent state
      assertionFailure()
    default:
      /// This is an unexpected error code
      fatalError()
    }
  }

  /// Type describing how the stream should flush data
  enum FlushBehavior {

    /// Only flush data if needed (corresponds to `Z_NO_FLUSH`)
    case noForcedFlush

    /// Flushes as much as possible.
    /// This does not guarantee that the stream end will be reached in a single `deflate`.
    /// If `deflate` returns an outcome where `isStreamEnd` is `false`, the caller should call `deflate` again with the `.finish` behavior.
    case finish

    fileprivate var flag: Int32 {
      switch self {
      case .noForcedFlush: Z_NO_FLUSH
      case .finish: Z_FINISH
      }
    }
  }

  /// The outcome of the `deflate` operation.
  struct DeflateOutcome {
    /// The number of bytes written to the output buffer
    let bytesWritten: Int

    /// The number of bytes read from the input buffer
    let bytesRead: Int

    /// Whether or not the stream is complete.
    /// Will only be set to `true` if `FlushBehavior.finish` is used.
    let isStreamEnd: Bool
  }

  /// Deflates some input into the output buffer.
  ///
  /// - Parameters:
  ///   - input:
  ///       The buffer to pull data from.
  ///       If `nil`, no data will be read.
  ///       This can be useful in conjunction with certain flush behaviors.
  ///   - output:
  ///       The output buffer to write data to.
  ///   - flushBehavior:
  ///       A value controlling how the stream flushes data.
  ///       See `FlushBehavior` documenation for specifics.
  /// - Returns:
  ///     A `DeflateOutcome` value describing what the stream accomplished.
  func deflate(
    _ input: UnsafeMutableRawBufferPointer? = nil,
    into output: UnsafeMutableRawBufferPointer,
    flushBehavior: FlushBehavior = .noForcedFlush
  ) -> DeflateOutcome {
    assert(c.next_in == nil)
    assert(c.avail_in == 0)
    assert(c.next_out == nil)
    assert(c.avail_out == 0)
    defer {
      /// Reset stream state
      c.next_in = nil
      c.avail_in = 0
      c.next_out = nil
      c.avail_out = 0
    }

    return (input ?? Self.emptyBuffer).withMemoryRebound(to: Bytef.self) { inputBytes in
      output.withMemoryRebound(to: Bytef.self) { outputBytes in
        c.next_in = inputBytes.baseAddress!
        c.avail_in = UInt32(inputBytes.count)
        c.next_out = outputBytes.baseAddress!
        c.avail_out = UInt32(outputBytes.count)
        defer {
          c.next_in = nil
          c.avail_in = 0
          c.next_out = nil
          c.avail_out = 0
        }

        let result = CZlib.deflate(&c, flushBehavior.flag)
        switch result {
        case Z_STREAM_END where flushBehavior == .finish, Z_OK:
          return DeflateOutcome(
            bytesWritten: c.next_out - outputBytes.baseAddress!,
            bytesRead: c.next_in - inputBytes.baseAddress!,
            isStreamEnd: result == Z_STREAM_END)
        default:
          /// The only issues here are related to misconfiguration, or not proving input/output.
          /// This seems like an acceptable tradeoff to keep the API simple.
          fatalError()
        }
      }
    }

  }

  /// `z_stream` is immovable (moving it causes `deflate` to return `Z_STREAM_ERROR`).
  /// This only works because `DeflateStream` is a class
  private var c: z_stream

  private static let emptyBuffer =
    UnsafeMutableRawBufferPointer
    .allocate(byteCount: 0, alignment: MemoryLayout<Bytef>.alignment)
}
