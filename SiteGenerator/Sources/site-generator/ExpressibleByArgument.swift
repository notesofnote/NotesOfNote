import ArgumentParser
import SystemPackage

extension FilePath: ExpressibleByArgument {
  public init?(argument: String) {
    self.init(argument)
  }
}
