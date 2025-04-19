// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "photocleaner",
    platforms: [.iOS(.v16)],
    products: [
        .library(
            name: "photocleaner",
            targets: ["photocleaner"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/RevenueCat/purchases-ios.git", from: "4.31.5")
    ],
    targets: [
        .target(
            name: "photocleaner",
            dependencies: [
                .product(name: "RevenueCat", package: "purchases-ios"),
                .product(name: "RevenueCatUI", package: "purchases-ios")
            ]
        )
    ]
) 