// swift-tools-version: 5.9
import PackageDescription
import Foundation

// Resolve the Info.plist path relative to this file so the linker flag works
// regardless of where Xcode's build system sets the working directory.
let infoPlistPath = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Sources/Resources/Info.plist")
    .path

let package = Package(
    name: "Provenance",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Provenance",
            path: "Sources",
            exclude: ["Resources/Info.plist", "Resources/Assets.xcassets"],
            linkerSettings: [
                .linkedFramework("CoreServices"),
                .linkedFramework("PDFKit"),
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", infoPlistPath
                ])
            ]
        )
    ]
)
