// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LinuxVM",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LinuxVM", targets: ["LinuxVM"])
    ],
    targets: [
        .executableTarget(
            name: "LinuxVM",
            path: "Sources/LinuxVM",
            linkerSettings: [
                .linkedFramework("Virtualization"),
                .linkedFramework("AppKit")
            ]
        )
    ]
)
