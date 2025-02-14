// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "sharing-grdb",
  platforms: [
    .iOS(.v13),
    .macOS(.v10_15),
    .tvOS(.v13),
    .watchOS(.v7),
  ],
  products: [
    .library(
      name: "SharingGRDB",
      targets: ["SharingGRDB"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift", from: "7.1.0"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.6.4"),
    .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.3.0"),
  ],
  targets: [
    .target(
      name: "SharingGRDB",
      dependencies: [
        .product(name: "GRDB", package: "GRDB.swift"),
        .product(name: "Sharing", package: "swift-sharing"),
      ]
    ),
    .testTarget(
      name: "SharingGRDBTests",
      dependencies: [
        "SharingGRDB",
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
      ]
    ),
  ]
)
