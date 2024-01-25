import NIOCore
import NIOFileSystem

import struct Foundation.Date

public struct TapeArchiveWriter: ~Copyable {
  public init(
    path: FilePath,
    replaceExistingFile: Bool,
    archiveName: String,
    modificationDate: Date = Date()
  ) async throws {
    self.deflateStream = DeflateStream()
    self.archiveWriter = try await FileWriter(
      fileSystem: .shared,
      path: path,
      options: .newFile(
        replaceExisting: replaceExistingFile))
    self.outputBuffer =
      bufferAllocator
      .buffer(capacity: Self.outputBufferCapacity)

    deflateStream.setHeader(
      fileName: archiveName,
      modificationDate: .distantFuture)
  }

  private let deflateStream: DeflateStream
  private let archiveWriter: FileWriter

  private let bufferAllocator: ByteBufferAllocator = .init()
  private var outputBuffer: ByteBuffer
  private static let outputBufferCapacity = 128 * 1024
}
