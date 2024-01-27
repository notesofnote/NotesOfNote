import SystemPackage
import TapeArchive

public enum Foo {
  public static let foo = "foo"

  public static func generateSite(at filePath: FilePath) async throws {
    var archiveWriter = try await TapeArchiveWriter(
      filePath: filePath,
      replaceExistingFile: true,
      archiveFileName: "static-site.tar")
    var index: TapeArchiveWriter.File = .init(
      name: "index.html",
      mode: 0o644)
    index.append("Hello, World!<br/>This site is generated using Swift!")
    try await archiveWriter.write(index)
    try await archiveWriter.finish()
  }
}
