import NIOFileSystem

import struct Foundation.Date

extension TapeArchiveWriter {
  public init(
    filePath: FilePath,
    replaceExistingFile: Bool
  ) async throws {
    try await self.init(
      destination: FileWriter(
        fileSystem: .shared,
        filePath: filePath,
        options: .newFile(
          replaceExisting: replaceExistingFile)))
  }
}
