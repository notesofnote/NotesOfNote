import NIOCore
import NIOFileSystem
import SystemPackage

import struct Foundation.Date

public struct TapeArchiveWriter: ~Copyable {
  public init(
    filePath: FilePath,
    replaceExistingFile: Bool,
    archiveFileName: String,
    archiveModificationDate: Date = Date()
  ) async throws {
    deflateStream = DeflateStream()
    archiveWriter = try await FileWriter(
      fileSystem: .shared,
      filePath: filePath,
      options: .newFile(
        replaceExisting: replaceExistingFile))
    bufferAllocator = ByteBufferAllocator()
    outputBuffer =
      bufferAllocator
      .buffer(capacity: Self.defaultOutputBufferCapacity)
    deflateStream.setHeader(
      fileName: archiveFileName,
      modificationDate: archiveModificationDate)
  }

  public mutating func write(_ file: File) async throws {
    let buffers = [
      [file.generateHeader(bufferAllocator: bufferAllocator)],
      file.chunks,
      [bufferAllocator.buffer(repeating: 0, count: file.requiredPaddingByteCount)],
    ].joined()

    for buffer in buffers {

      /// `outputBuffer` should be reset every iteration
      precondition(outputBuffer.writerIndex == 0)
      defer { outputBuffer.clear() }

    }
  }

  public struct File {
    init(
      name: String,
      mode: UInt32,
      owner: ProcessOwner = ProcessOwner(),
      lastModificationDate: Date = Date()
    ) {
      precondition(name.utf8.count < 100)
      self.name = name
      self.mode = mode
      self.owner = owner
      self.lastModificationDate = lastModificationDate
    }

    fileprivate func generateHeader(bufferAllocator: ByteBufferAllocator) -> ByteBuffer {
      /// https://en.wikipedia.org/wiki/Tar_(computing)#File_format
      var header = bufferAllocator.buffer(capacity: 512)
      /// Write file name
      do {
        let utf8 = name.utf8
        precondition(utf8.count < 100)
        header.writeBytes(utf8)
        header.writeRepeatingByte(0, count: 100 - utf8.count)
      }
      /// Write mode, userID and groupID
      for value in [mode, owner.id, owner.groupID] {
        let fieldWidth = 8
        let string = String(value, radix: 8) + " \0"
        let utf8 = string.utf8
        precondition(utf8.count < fieldWidth)
        header.writeRepeatingByte(0, count: fieldWidth - utf8.count)
        header.writeBytes(utf8)
      }
      /// Write file size and modification time
      for value in [fileSize, lastModificationTime] {
        let fieldWidth = 12
        let string = String(value, radix: 8) + " "
        let utf8 = string.utf8
        precondition(utf8.count < fieldWidth)
        header.writeRepeatingByte(0, count: fieldWidth - utf8.count)
        header.writeBytes(utf8)
      }
      /// Write temporary checksum (will be updated at end)
      header.writeRepeatingByte(32 /* ASCII space */, count: 8)
      /// Write file type flag ("Normal File")
      header.writeBytes([0])
      /// Write empty field ("Name of Linked File" does not apply)
      header.writeRepeatingByte(0, count: 100)
      /// Write Universal tar indicator
      header.writeString("ustar\000")
      /// Write user name and group name
      for value in [owner.name, owner.groupName] {
        let fieldWidth = 32
        let utf8 = value.utf8
        precondition(utf8.count < fieldWidth)
        header.writeBytes(utf8)
        header.writeRepeatingByte(0, count: fieldWidth - utf8.count)
      }
      /// Write device major/minor numbers (experimentally determined to always be 0)
      header.writeString("000000 \0")
      header.writeString("000000 \0")
      /// Write empty field ("Filename Prefix" is unused)
      header.writeRepeatingByte(0, count: 155)
      precondition(header.readerIndex == 500)
      /// Write 0s until the end of the header
      header.writeRepeatingByte(0, count: header.writableBytes)
      /// Generate a checksum and write it into the appropriate location
      do {
        let fieldWidth = 8
        let checksum = header.readableBytesView.map(Int.init).reduce(0, +)
        let string = String(checksum, radix: 8) + "\0 "
        let paddedString = String(repeating: "0", count: fieldWidth - string.count) + string
        let utf8 = paddedString.utf8
        precondition(utf8.count < fieldWidth)
        header.setBytes(utf8, at: 148)
      }
      return header
    }

    fileprivate let name: String
    fileprivate let mode: UInt32
    fileprivate let owner: ProcessOwner
    fileprivate let lastModificationDate: Date
    fileprivate var chunks: [ByteBuffer] = []
    fileprivate var fileSize: Int {
      chunks.map(\.readableBytes).reduce(0, +)
    }

    /// Files in a tape archive must be padded with zeroes so that the full length is divisible by 512
    fileprivate var requiredPaddingByteCount: Int {
      let remainder = fileSize % 512
      if remainder > 0 {
        return 512 - remainder
      } else {
        return 0
      }
    }

    private var lastModificationTime: Int {
      Int(lastModificationDate.timeIntervalSince1970)
    }
  }

  private let deflateStream: DeflateStream
  private let archiveWriter: FileWriter

  private let bufferAllocator: ByteBufferAllocator
  private var outputBuffer: ByteBuffer
  private static let defaultInputBufferCapacity = 16 /* kiB */ * 1024
  private static let defaultOutputBufferCapacity = 128 /* kiB */ * 1024
}
