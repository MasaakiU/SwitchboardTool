// swift-tools-version:5.9
// Switchboard Tool (SBT): a small resident app that replaces the parts of BetterTouchTool I use.
//   CMultitouch     entry point to Apple's private MultitouchSupport framework (C)
//   TouchProbe      test tool (log finger data, verify two-finger tap → right click)
//   SwitchboardTool the Agent: menu-bar resident
import PackageDescription

let package = Package(
    name: "SwitchboardTool",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CMultitouch", path: "Sources/CMultitouch"),
        .executableTarget(
            name: "TouchProbe",
            dependencies: ["CMultitouch"],
            path: "Sources/TouchProbe",
            linkerSettings: [.linkedFramework("AppKit")]
        ),
        .executableTarget(
            name: "SwitchboardTool",
            dependencies: ["CMultitouch"],
            path: "Sources/SwitchboardTool",
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("ServiceManagement")]
        ),
    ]
)
