// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SpeakerNotes",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "SpeakerNotes", targets: ["SpeakerNotesApp"]),
        .library(name: "SpeakerNotesCore", targets: ["SpeakerNotesCore"]),
    ],
    targets: [
        // Notes parsing with no UI: splitting into slides and reading Markdown blocks.
        .target(name: "SpeakerNotesCore"),
        // The macOS app: a floating panel, menu bar item and global hotkeys.
        .executableTarget(
            name: "SpeakerNotesApp",
            dependencies: ["SpeakerNotesCore"],
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        .testTarget(name: "SpeakerNotesCoreTests", dependencies: ["SpeakerNotesCore"]),
    ]
)
