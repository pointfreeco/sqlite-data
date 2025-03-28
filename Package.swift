// swift-tools-version: 6.0

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
    .package(url: "https://github.com/groue/GRDB.swift", from: "7.4.0"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.6.4"),
    .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.5.0"),
    .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.3.0"),
    .package(url: "https://github.com/pointfreeco/swift-structured-queries", branch: "main"),
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
        .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
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
    .testTarget(
      name: "StructuredQueriesGRDBTests",
      dependencies: [
        "StructuredQueriesGRDB",
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
      ]
    )
  ],
  swiftLanguageModes: [.v6]
)

#if !os(Windows)
  // Add the documentation compiler plugin if possible
  package.dependencies.append(
    .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0")
  )
#endif
