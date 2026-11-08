// swift-tools-version:5.9
import PackageDescription

// Arnés de verificación: compila y ejecuta la lógica de dominio (Core + Vision)
// en macOS, sin Xcode, sin iPhone y sin XCTest (no viene en Command Line Tools).
let paquete = Package(
    name: "BodegaVerificacion",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Verificacion", path: "Sources/Verificacion"),
    ]
)
