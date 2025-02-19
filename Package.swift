// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "sharing-grdb",
  platforms: [
    .iOS(.v16),
    .macOS(.v13),
    .tvOS(.v16),
    .watchOS(.v10),
  ],
  products: [
    .library(
      name: "SharingGRDB",
      targets: ["SharingGRDB"]
    ),
    .library(
      name: "StructuredQueriesGRDB",
      targets: ["StructuredQueriesGRDB"]
    ),
    .library(
      name: "StructuredQueriesGRDBCore",
      targets: ["StructuredQueriesGRDBCore"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift", from: "7.1.0"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.6.4"),
    .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.3.0"),
    .package(url: "https://github.com/pointfreeco/swift-structured-queries", branch: "main"),
    //.package(path: "../swift-structured-queries")
  ],
  targets: [
    .target(
      name: "SharingGRDB",
      dependencies: [
        "StructuredQueriesGRDBCore",
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

    .target(
      name: "StructuredQueriesGRDBCore",
      dependencies: [
        .product(name: "GRDB", package: "GRDB.swift"),
        .product(name: "StructuredQueriesCore", package: "swift-structured-queries"),
      ]
    ),
    .target(
      name: "StructuredQueriesGRDB",
      dependencies: [
        "StructuredQueriesGRDBCore",
        .product(name: "StructuredQueries", package: "swift-structured-queries"),
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)

#if !os(Windows)
  // Add the documentation compiler plugin if possible
  package.dependencies.append(
    .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0")
  )
#endif
