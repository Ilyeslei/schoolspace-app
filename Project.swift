// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "SchoolSpaceApp",
    platforms: [.iOS(.v26)],
    products: [
        .executable(name: "SchoolSpaceApp", targets: ["SchoolSpaceApp"])
    ],
    targets: [
        .executableTarget(
            name: "SchoolSpaceApp",
            path: "Sources",
            resources: [.process("Assets.xcassets")]
        )
    ]
)
