// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Vauchi",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(name: "Vauchi", targets: ["Vauchi"])
    ],
    targets: [
        .target(
            name: "Vauchi",
            path: "Vauchi",
            exclude: ["Info.plist"],
            sources: [
                "ContentView.swift",
                "VauchiApp.swift",
                "Services/VauchiRepository.swift",
                "Services/KeychainService.swift",
                "Services/SettingsService.swift",
                "Services/NetworkMonitor.swift",
                "Services/BackgroundSyncService.swift",
                "Services/ContactActions.swift",
                "ViewModels/VauchiViewModel.swift",
                "Views/ContactsView.swift",
                "Views/ContactDetailView.swift",
                "Views/ExchangeView.swift",
                "Views/HomeView.swift",
                "Views/QRScannerView.swift",
                "Views/SettingsView.swift",
                "Views/SetupView.swift",
                "Generated/vauchi_mobile.swift"
            ]
        ),
        .testTarget(
            name: "VauchiTests",
            dependencies: ["Vauchi"],
            path: "VauchiTests"
        )
    ]
)
