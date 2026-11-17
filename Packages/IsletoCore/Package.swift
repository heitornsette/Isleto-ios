// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IsletoCore",
    platforms: [
        .iOS(.v17),
        // macOS only so the tests can also run with `swift test` on the CI host.
        .macOS(.v14),
    ],
    products: [
        .library(name: "IsletoCore", targets: ["IsletoCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", "7.0.0"..<"8.0.0"),
    ],
    targets: [
        .target(
            name: "IsletoCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(
            name: "IsletoCoreTests",
            dependencies: [
                "IsletoCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
    ]
)
