import NIOFileSystem

/// Type for writing data to file
final class FileWriter {
  init(
    fileSystem: FileSystem,
    filePath: FilePath,
    options: OpenOptions.Write
  ) async throws {
    /// Set up the file handle and writer that will write to the output file.
    _fileHandle =
      try await fileSystem
      .openFile(forWritingAt: filePath, options: options)
  }

  /// Writes a sequence of bytes, potentially to a buffer.
  /// May flush the buffer to the output file if needed.
  @discardableResult
  func write(contentsOf sequence: some Sequence<UInt8>) async throws -> Int64 {
    try await withFileHandle { handle in
      let bytesWritten = try await handle.write(
        contentsOf: sequence,
        toAbsoluteOffset: fileOffset)
      fileOffset += bytesWritten
      return bytesWritten
    }
  }

  /// Closes the managed file handle
  func close() async throws {
    try await withFileHandle { handle in
      try await handle.close()
    }
    isOpen = false
  }

  deinit {
    if isOpen {
      Task<Void, Never> { [_fileHandle] in
        do {
          try await _fileHandle.close()
        } catch {
          assertionFailure()
        }
      }
    }
  }

  private func withFileHandle<T>(
    _ body: (inout WriteFileHandle) async throws -> T
  )
    async rethrows
    -> T
  {
    precondition(isOpen)

    do {
      return try await body(&_fileHandle)
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
  private var fileOffset: Int64 = 0

  /// The file handle should only be accessed via the `withFileHandle` method.
  private var _fileHandle: WriteFileHandle
}
