import NIOCore
import NIOFileSystem
import SystemPackage

import struct Foundation.Date

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

  /// Writes any pending bytes to the output file.
  public consuming func finish() async throws {
    /// Write two consecutive zero-filled (512 byte) records per the tar spec
    try await write(bufferAllocator.buffer(repeating: 0, count: 512 * 2))

    while true {
      let outcome = try await writeWrittenOutput { [deflateStream] outputBuffer in
        deflateStream.deflate(into: &outputBuffer, flushBehavior: .finish)
      }
      if outcome.isStreamEnd {
        break
      }
    }

    try await archiveWriter.flush()
  }

  /// Write a file to this archive.
  /// Does not guarantee all necessary byte will be written to the output file unless `finish` is called.
  public mutating func write(_ file: File) async throws {
    try await write(file.generateHeader(bufferAllocator: bufferAllocator))
    for chunk in file.chunks {
      try await write(chunk)
    }
    try await write(bufferAllocator.buffer(repeating: 0, count: file.requiredPaddingByteCount))
  }

  public struct File {
    public init(
      name: String,
      mode: UInt32,
      owner: Owner = .process,
      lastModificationDate: Date = Date()
    ) {
      precondition(name.utf8.count < 100)
      self.name = name
      self.mode = mode
      self.owner = owner
      self.lastModificationDate = lastModificationDate
    }

    public struct Owner {
      public static var process: Owner {
        let groupID = getgid()
        return Owner(
          id: getuid(),
          groupID: groupID,
          name: String(cString: getlogin()),
          groupName: String(cString: getgrgid(groupID).pointee.gr_name)
        )
      }

      let id: UInt32
      let groupID: UInt32
      let name: String
      let groupName: String
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
    fileprivate let owner: Owner
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

  /// Write the readable bytes of `buffer` to the archive.
  private mutating func write(_ buffer: ByteBuffer) async throws {
    var mutableBuffer = buffer
    while mutableBuffer.readableBytes > 0 {
      try await writeWrittenOutput { [deflateStream] outputBuffer in
        let outcome = deflateStream.deflate(
          &mutableBuffer, into: &outputBuffer, flushBehavior: .flushWhenNeeded)
        precondition(outcome.bytesRead > 0 || outcome.bytesWritten > 0)
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

    try await archiveWriter.write(contentsOf: outputBuffer.readableBytesView)

    return result
  }

  private let deflateStream: DeflateStream
  private let archiveWriter: FileWriter
  private var outputBuffer: ByteBuffer

  private let bufferAllocator: ByteBufferAllocator
  private static let defaultInputBufferCapacity = 16 /* kiB */ * 1024
  private static let defaultOutputBufferCapacity = 128 /* kiB */ * 1024
}
