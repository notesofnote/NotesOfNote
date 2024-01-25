import NIOFileSystem

/// Type for writing data to file
final class FileWriter {
  init(
    fileSystem: FileSystem,
    path: FilePath,
    options: OpenOptions.Write
  ) async throws {
    /// Set up the file handle and writer that will write to the output file.
    _fileHandle =
      try await fileSystem
      .openFile(forWritingAt: path, options: options)
    _bufferedWriter = _fileHandle.bufferedWriter()
  }

  /// Writes a sequence of bytes, potentially to a buffer.
  /// May flush the buffer to the output file if needed.
  @discardableResult
  func write(contentsOf sequence: some Sequence<UInt8>) async throws -> Int64 {
    try await withProperties { _, writer in
      try await writer.write(contentsOf: sequence)
    }
  }

  /// Flushes the write buffer to the output file
  func flush() async throws {
    try await withProperties { _, writer in
      try await writer.flush()
    }
  }

  /// Closes the managed file handle
  func close() async throws {
    try await withProperties { handle, _ in
      try await handle.close()
    }
    isOpen = false
  }

  deinit {
    if isOpen {
      Task<Void, Never> {
        do {
          try await _fileHandle.close()
        } catch {
          assertionFailure()
        }
      }
    }
  }

  private func withProperties<T>(
    _ body: (inout WriteFileHandle, inout BufferedWriter) async throws -> T
  )
    async rethrows
    -> T
  {
    precondition(isOpen)

    do {
      return try await body(&_fileHandle, &_bufferedWriter)
    } catch {
      do {
        isOpen = false
        try await _fileHandle.close()
      } catch {
        /// Suppress the `close` error in favor of the actual error that was thrown.
        assertionFailure()
      }
      throw error
    }
  }

  private typealias BufferedWriter = NIOFileSystem.BufferedWriter<WriteFileHandle>

  private var isOpen = true

  /// The following properties should only be accessed via the `withProperties` method.
  private var _bufferedWriter: BufferedWriter
  private var _fileHandle: WriteFileHandle
}
