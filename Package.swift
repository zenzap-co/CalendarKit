// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "CalendarKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v13),
        .tvOS(.v11),
        .macCatalyst(.v13)
    ],
    products: [
        .library(
            name: "CalendarKit",
            targets: ["CalendarKit"]),
    ],
    targets: [
        .target(name: "CalendarKit",
                path: "Sources")
    ]
)
