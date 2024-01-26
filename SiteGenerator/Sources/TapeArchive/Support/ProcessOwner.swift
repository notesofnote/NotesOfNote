#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

struct ProcessOwner {
  init(
    id: UInt32? = nil,
    groupID: UInt32? = nil,
    name: String? = nil,
    groupName: String? = nil
  ) {
    self.id = id ?? getuid()
    self.groupID = groupID ?? getgid()
    self.name = name ?? String(cString: getlogin())
    self.groupName = groupName ?? String(cString: getgrgid(self.groupID).pointee.gr_name)
  }

  let id: UInt32
  let groupID: UInt32
  let name: String
  let groupName: String
}
