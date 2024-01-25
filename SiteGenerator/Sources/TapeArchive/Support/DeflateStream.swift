import CZlib

final class DeflateStream {
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

  enum FlushBehavior {
    case noFlush
    case finish

    fileprivate var flag: Int32 {
      switch self {
      case .noFlush: Z_NO_FLUSH
      case .finish: Z_FINISH
      }
    }
  }

  struct DeflateOutcome {
    let bytesWritten: Int
    let bytesRead: Int
    let isStreamEnd: Bool
  }

  func deflate(
    _ input: UnsafeMutableRawBufferPointer? = nil,
    into output: UnsafeMutableRawBufferPointer,
    flushBehavior: FlushBehavior = .noFlush
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
