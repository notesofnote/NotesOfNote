import NIOCore
import NIOFileSystem
import SystemPackage

import struct Foundation.Date

// For getuid and getgid
#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

public struct TapeArchiveWriter: ~Copyable {
  public init(
    filePath: FilePath,
    replaceExistingFile: Bool,
    archiveFileName: String,
    archiveModificationDate: Date = Date()
  ) async throws {
    self.deflateStream = DeflateStream()
    self.archiveWriter = try await FileWriter(
      fileSystem: .shared,
      filePath: filePath,
      options: .newFile(
        replaceExisting: replaceExistingFile))
    self.outputBuffer =
      ByteBufferAllocator()
      .buffer(capacity: Self.outputBufferCapacity)
    deflateStream.setHeader(
      fileName: archiveFileName,
      modificationDate: archiveModificationDate)
  }

  public func writeFile(
    fileName: String,
    fileMode: Int,
    ownerID: UInt32 = getuid(),
    groupID: UInt32 = getgid()
  ) async throws {

  }

  private let deflateStream: DeflateStream
  private let archiveWriter: FileWriter

  private var outputBuffer: ByteBuffer
  private static let outputBufferCapacity = 128 * 1024
}
