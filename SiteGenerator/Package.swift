// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "NotesOfNoteSiteGenerator",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(
      name: "notes-of-note-site-generator",
      targets: ["notes-of-note-site-generator"])
  ],
  dependencies: [
    .package(
      url: "https://github.com/apple/swift-argument-parser",
      from: "1.3.0"
    ),
    .package(
      url: "https://github.com/apple/swift-nio.git",
      from: "2.63.0" /* _NIOFileSystem introduced */),
  ],
  targets: [
    .target(
      name: "CZlib",
      linkerSettings: [
        .linkedLibrary("z")
      ]),
    .target(
      name: "TapeArchive",
      dependencies: [
        "CZlib",
        .product(name: "_NIOFileSystem", package: "swift-nio"),
      ]
    ),
    .testTarget(
      name: "TapeArchiveTests",
      dependencies: [
        "TapeArchive"
      ]
    ),
    .target(
      name: "SiteGenerator",
      dependencies: [
        "TapeArchive"
      ],
      path: "Sources/SiteGenerator"
    ),
    .executableTarget(
      name: "notes-of-note-site-generator",
      dependencies: [
        "SiteGenerator",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "_NIOFileSystem", package: "swift-nio"),
      ],
      path: "Sources/site-generator"
    ),
  ]
)
