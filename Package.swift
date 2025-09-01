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
      name: "SharingGRDBCore",
      targets: ["SharingGRDBCore"]
    ),
    .library(
      name: "SharingGRDBTestSupport",
      targets: ["SharingGRDBTestSupport"]
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
    .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.3.3"),
    .package(url: "https://github.com/groue/GRDB.swift", from: "7.4.0"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.9.0"),
    .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.5.0"),
    .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.3.0"),
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.18.4"),
    .package(url: "https://github.com/pointfreeco/swift-structured-queries", branch: "custom-functions"),
  ],
  targets: [
    .target(
      name: "SharingGRDB",
      dependencies: [
        "SharingGRDBCore",
        "StructuredQueriesGRDB",
      ]
    ),
    .target(
      name: "SharingGRDBCore",
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
        "SharingGRDBTestSupport",
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
        .product(name: "StructuredQueries", package: "swift-structured-queries"),
      ]
    ),
    .target(
      name: "SharingGRDBTestSupport",
      dependencies: [
        "SharingGRDB",
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
        .product(name: "StructuredQueriesTestSupport", package: "swift-structured-queries"),
      ]
    ),
    .target(
      name: "StructuredQueriesGRDBCore",
      dependencies: [
        .product(name: "GRDB", package: "GRDB.swift"),
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
        .product(name: "StructuredQueriesCore", package: "swift-structured-queries"),
        .product(name: "StructuredQueriesSQLiteCore", package: "swift-structured-queries"),
      ]
    ),
    .target(
      name: "StructuredQueriesGRDB",
      dependencies: [
        "StructuredQueriesGRDBCore",
        .product(name: "StructuredQueries", package: "swift-structured-queries"),
        .product(name: "StructuredQueriesSQLite", package: "swift-structured-queries"),
      ]
    ),
    .testTarget(
      name: "StructuredQueriesGRDBTests",
      dependencies: [
        "StructuredQueriesGRDB",
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
        .product(name: "StructuredQueries", package: "swift-structured-queries"),
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)

let swiftSettings: [SwiftSetting] = [
  .enableUpcomingFeature("MemberImportVisibility"),
  // .unsafeFlags([
  //   "-Xfrontend",
  //   "-warn-long-function-bodies=50",
  //   "-Xfrontend",
  //   "-warn-long-expression-type-checking=50",
  // ])
]

for index in package.targets.indices {
  package.targets[index].swiftSettings = swiftSettings
}

#if !os(Windows)
  // Add the documentation compiler plugin if possible
  package.dependencies.append(
    .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0")
  )
#endif
