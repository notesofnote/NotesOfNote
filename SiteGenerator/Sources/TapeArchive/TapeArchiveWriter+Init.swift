import NIOFileSystem

import struct Foundation.Date

extension TapeArchiveWriter {
  public init(
    filePath: FilePath,
    replaceExistingFile: Bool,
    archiveFileName: String,
    archiveModificationDate: Date = Date()
  ) async throws {
    try await self.init(
      destination: FileWriter(
        fileSystem: .shared,
        filePath: filePath,
        options: .newFile(
          replaceExisting: replaceExistingFile)))
  }
}
