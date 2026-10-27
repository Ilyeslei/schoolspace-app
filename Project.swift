// SchoolSpaceApp - Project configuration
// Ne pas modifier directement, utilisez Xcode pour gérer le projet

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
