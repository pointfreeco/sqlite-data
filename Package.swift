// swift-tools-version: 6.1

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
      name: "StructuredQueriesGRDB",
      targets: ["StructuredQueriesGRDB"]
    ),
    .library(
      name: "StructuredQueriesGRDBCore",
      targets: ["StructuredQueriesGRDBCore"]
    ),
  ],
  traits: [
    .trait(
      name: "SharingGRDBTagged",
      description: "Introduce SharingGRDB conformances to the swift-tagged package."
    ),
    .trait(
      name: "SharingGRDBSwiftLog",
      description: "Use swift-log instead of OSLog for logging."
    ),
    .default(enabledTraits: ["SharingGRDBTagged"]),
  ],
  dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift", from: "7.4.0"),
    .package(url: "https://github.com/apple/swift-collections", from: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.9.0"),
    .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.3.0"),
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.0.0"),
    .package(
      url: "https://github.com/pointfreeco/swift-structured-queries",
      from: "0.12.1",
      traits: [
        .trait(name: "StructuredQueriesTagged", condition: .when(traits: ["SharingGRDBTagged"])),
      ]
    ),
    .package(url: "https://github.com/pointfreeco/swift-tagged", from: "0.10.0"),
    .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.5.0"),
    .package(url: "https://github.com/apple/swift-log", from: "1.6.4"),
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
        .product(name: "OrderedCollections", package: "swift-collections"),
        .product(name: "Sharing", package: "swift-sharing"),
        .product(name: "StructuredQueriesCore", package: "swift-structured-queries"),
        .product(
          name: "Tagged",
          package: "swift-tagged",
          condition: .when(traits: ["SharingGRDBTagged"])
        ),
        .product(
          name: "Logging",
          package: "swift-log",
          condition: .when(traits: ["SharingGRDBSwiftLog"])
        )
      ]
    ),
    .testTarget(
      name: "SharingGRDBTests",
      dependencies: [
        "SharingGRDB",
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
        .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
        .product(name: "SnapshotTestingCustomDump", package: "swift-snapshot-testing"),
        .product(name: "StructuredQueries", package: "swift-structured-queries"),
      ]
    ),
    .target(
      name: "StructuredQueriesGRDBCore",
      dependencies: [
        .product(name: "GRDB", package: "GRDB.swift"),
        .product(name: "Dependencies", package: "swift-dependencies"),
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
