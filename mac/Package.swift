// swift-tools-version:5.7
import PackageDescription

// Tests compile the same downloader and speech client used by the app.
let package = Package(name: "DictationTranscription", platforms: [.macOS(.v12)],
    dependencies: [.package(url: "https://github.com/exPHAT/SwiftWhisper", revision: "c340197966ebd264f3135d3955874b40f8ed58bc")],
    targets: [
        .target(name: "DictationTranscription", dependencies: ["SwiftWhisper"],
                path: "Core/Transcription", exclude: ["GenericTranscriptionClient.swift"]),
        .testTarget(name: "ModelTests", dependencies: ["DictationTranscription"], path: "Tests")
    ])
