// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ImportantTodo",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "ImportantTodo", targets: ["ImportantTodo"])],
    targets: [
        .target(name: "TodoCore"),
        .executableTarget(name: "ImportantTodo", dependencies: ["TodoCore"]),
        .testTarget(name: "TodoCoreTests", dependencies: ["TodoCore"])
    ],
    swiftLanguageModes: [.v5]
)
