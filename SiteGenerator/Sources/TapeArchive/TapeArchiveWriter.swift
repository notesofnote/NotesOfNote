import NIOCore

import struct Foundation.Date

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

public struct TapeArchiveWriter {
  init(
    destination: some ByteBufferConsumer
  ) async throws {
    self.destination = destination
    bufferAllocator = ByteBufferAllocator()
  }

  /// Writes any pending bytes to the output file.
  public mutating func finish() async throws {
    /// Write two consecutive zero-filled (512 byte) records per the tar spec
    try await destination.consumeReadableBytes(
      of: bufferAllocator.buffer(
        repeating: 0,
        count: 512 * 2))
    try await destination.finishConsumingBytes()
  }

  /// Write a file to this archive.
  /// Does not guarantee all necessary byte will be written to the output file unless `finish` is called.
  public mutating func write(_ file: File) async throws {
    try await destination.consumeReadableBytes(
      of: file.generateHeader(
        bufferAllocator: bufferAllocator))
    for chunk in file.chunks {
      try await destination.consumeReadableBytes(of: chunk)
    }
    try await destination.consumeReadableBytes(
      of: bufferAllocator.buffer(
        repeating: 0,
        count: file.requiredPaddingByteCount))
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
        let id = getuid()
        let groupID = getgid()

        /// Get user name
        let name = withUnsafeTemporaryAllocation(
          of: UInt8.self,
          capacity: sysconf(Int32(_SC_GETPW_R_SIZE_MAX))
        ) { buffer in
          var pw = passwd()
          var pwRef: UnsafeMutablePointer<passwd>?
          let result = getpwuid_r(
            id, &pw, buffer.baseAddress!, buffer.count,
            &pwRef)
          guard result == 0 else { fatalError() }
          return String(cString: pwRef!.pointee.pw_name)
        }

        /// Get group name
        let groupName = withUnsafeTemporaryAllocation(
          of: UInt8.self,
          capacity: sysconf(Int32(_SC_GETGR_R_SIZE_MAX))
        ) { buffer in
          var grp = group()
          var grpRef: UnsafeMutablePointer<group>?
          let result = getgrgid_r(groupID, &grp, buffer.baseAddress!, buffer.count, &grpRef)
          guard result == 0 else { fatalError() }
          return String(cString: grp.gr_name)
        }

        return Owner(
          id: id,
          groupID: groupID,
          name: name,
          groupName: groupName)
      }

      let id: UInt32
      let groupID: UInt32
      let name: String
      let groupName: String
    }

    public mutating func append(_ string: String) {
      chunks.append(chunkAllocator.buffer(string: string))
    }

    public mutating func append(_ bytes: some Sequence<UInt8>) {
      chunks.append(chunkAllocator.buffer(bytes: bytes))
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
        header.writeRepeatingByte(0x30 /* ASCII zero */, count: fieldWidth - utf8.count)
        header.writeBytes(utf8)
      }
      /// Write file size and modification time
      for value in [fileSize, lastModificationTime] {
        let fieldWidth = 12
        let string = String(value, radix: 8) + " "
        let utf8 = string.utf8
        precondition(utf8.count <= fieldWidth)
        header.writeRepeatingByte(0x30 /* ASCII zero */, count: fieldWidth - utf8.count)
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
      precondition(header.writerIndex == 500)
      /// Write 0s until the end of the header
      header.writeRepeatingByte(0, count: header.writableBytes)
      /// Generate a checksum and write it into the appropriate location
      do {
        let fieldWidth = 8
        let checksum = header.readableBytesView.map(Int.init).reduce(0, +)
        let string = String(checksum, radix: 8) + "\0 "
        let paddedString = String(repeating: "0", count: fieldWidth - string.count) + string
        let utf8 = paddedString.utf8
        precondition(utf8.count <= fieldWidth)
        header.setBytes(utf8, at: 148)
      }
      return header
    }

    fileprivate let name: String
    fileprivate let mode: UInt32
    fileprivate let owner: Owner
    fileprivate let lastModificationDate: Date
    fileprivate let chunkAllocator = ByteBufferAllocator()
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

  private let bufferAllocator: ByteBufferAllocator
  private var destination: any ByteBufferConsumer
}
