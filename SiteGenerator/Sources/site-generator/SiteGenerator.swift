import ArgumentParser
import NIOFileSystem
import SiteGenerator

@main
struct SiteGenerator: AsyncParsableCommand {
  static let configuration: CommandConfiguration = .init(
    subcommands: [
      GenerateSite.self
    ])
}

struct GenerateSite: AsyncParsableCommand {
  @Option
  var outputFile: FilePath

  func run() async throws {

  }
}
