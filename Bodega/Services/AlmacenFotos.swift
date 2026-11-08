import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import OSLog

/// Errores del almacén de fotos.
enum ErrorAlmacenFotos: LocalizedError {
    case noSePudoPrepararLaImagen
    case noSePudoRedimensionar
    case noSePudoCrearElArchivo
    case noSePudoEscribirElArchivo

    var errorDescription: String? {
        switch self {
        case .noSePudoPrepararLaImagen:
            return "No se pudo procesar la imagen."
        case .noSePudoRedimensionar:
            return "No se pudo redimensionar la foto."
        case .noSePudoCrearElArchivo:
            return "No se pudo crear el archivo de la foto."
        case .noSePudoEscribirElArchivo:
            return "No se pudo guardar la foto en el disco."
        }
    }
}

/// Almacén de fotos en disco.
///
/// Las imágenes se guardan como archivos JPEG dentro de `Documents/Fotos/`
/// y la base de datos solo guarda la ruta relativa (por ejemplo `Fotos/1A2B.jpg`).
///
/// Sin `import UIKit`: se puede compilar y probar en macOS.
final class AlmacenFotos {

    /// Instancia compartida por toda la app.
    static let compartido = AlmacenFotos()

    /// Caché de bytes ya leídos del disco, para no releer las fotos al hacer scroll.
    private let cache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 200
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    private let logger = Logger(subsystem: "com.bodega.app", category: "AlmacenFotos")
    private let fm = FileManager.default

    private init() {
        asegurarCarpetas()
    }

    // MARK: - Rutas base

    /// Carpeta `Documents` de la app.
    static var raizDocumentos: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
    }

    /// Carpeta donde viven las fotos.
    var carpetaFotos: URL {
        AlmacenFotos.raizDocumentos.appendingPathComponent("Fotos", isDirectory: true)
    }

    /// Crea `Fotos/`, `Backups/` y `Exportaciones/` si no existen.
    func asegurarCarpetas() {
        let carpetas = [
            AlmacenFotos.raizDocumentos.appendingPathComponent("Fotos", isDirectory: true),
            AlmacenFotos.raizDocumentos.appendingPathComponent("Backups", isDirectory: true),
            AlmacenFotos.raizDocumentos.appendingPathComponent("Exportaciones", isDirectory: true)
        ]
        for carpeta in carpetas {
            guard !fm.fileExists(atPath: carpeta.path) else { continue }
            do {
                try fm.createDirectory(at: carpeta, withIntermediateDirectories: true)
            } catch {
                logger.error("No se pudo crear la carpeta \(carpeta.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Traduce una ruta relativa (`Fotos/abc.jpg`) a una URL absoluta.
    func url(paraRuta ruta: String) -> URL {
        if ruta.isEmpty { return carpetaFotos }
        return AlmacenFotos.raizDocumentos.appendingPathComponent(ruta)
    }

    // MARK: - Guardar

    /// Redimensiona la imagen y la guarda como JPEG (calidad 0,7).
    ///
    /// El redimensionado usa `CGImageSourceCreateThumbnailAtIndex` de ImageIO,
    /// que además respeta la orientación EXIF. Devuelve la ruta relativa
    /// (`Fotos/<UUID>.jpg`).
    ///
    /// - Throws: `ErrorAlmacenFotos` si no se puede preparar o escribir la foto.
    ///   Se propaga el error (en vez de devolver "") porque quien llama usa
    ///   `try?`, que solo distingue el fallo si la función lanza de verdad;
    ///   devolver "" se interpretaría como una ruta válida y se guardaría
    ///   una foto vacía en `rutasFotos`.
    func guardar(_ imagen: CGImage) throws -> String {
        let lado = max(200, Preferencias.ladoMaximoFoto)

        // ImageIO trabaja sobre fuentes (CGImageSource), así que primero codificamos
        // la imagen cruda a JPEG intermedio y de ahí sacamos la miniatura.
        guard let datosIntermedios = AlmacenFotos.codificarJPEG(imagen, calidad: 0.95),
              let fuente = CGImageSourceCreateWithData(datosIntermedios as CFData, nil) else {
            logger.error("No se pudo preparar la imagen para guardarla")
            print("AlmacenFotos.guardar(imagen): no se pudo preparar la imagen")
            throw ErrorAlmacenFotos.noSePudoPrepararLaImagen
        }

        let opciones: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: lado
        ]

        guard let miniatura = CGImageSourceCreateThumbnailAtIndex(fuente, 0, opciones as CFDictionary) else {
            logger.error("No se pudo generar la miniatura de la imagen")
            print("AlmacenFotos.guardar(imagen): no se pudo generar la miniatura")
            throw ErrorAlmacenFotos.noSePudoRedimensionar
        }

        let ruta = "Fotos/\(UUID().uuidString).jpg"
        let destino = url(paraRuta: ruta)

        guard let escritura = CGImageDestinationCreateWithURL(destino as CFURL,
                                                             UTType.jpeg.identifier as CFString,
                                                             1,
                                                             nil) else {
            logger.error("No se pudo crear el destino JPEG en \(destino.path, privacy: .public)")
            print("AlmacenFotos.guardar(imagen): no se pudo crear el archivo destino")
            throw ErrorAlmacenFotos.noSePudoCrearElArchivo
        }

        let propiedades: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.7
        ]
        CGImageDestinationAddImage(escritura, miniatura, propiedades as CFDictionary)

        guard CGImageDestinationFinalize(escritura) else {
            logger.error("No se pudo escribir el JPEG en \(destino.path, privacy: .public)")
            print("AlmacenFotos.guardar(imagen): no se pudo escribir el archivo")
            throw ErrorAlmacenFotos.noSePudoEscribirElArchivo
        }

        return ruta
    }

    /// Guarda bytes JPEG que ya vienen listos (por ejemplo de la cámara).
    /// Devuelve la ruta relativa (`Fotos/<UUID>.jpg`).
    ///
    /// - Throws: `ErrorAlmacenFotos.noSePudoEscribirElArchivo` si no se puede escribir.
    func guardar(_ data: Data) throws -> String {
        let ruta = "Fotos/\(UUID().uuidString).jpg"
        let destino = url(paraRuta: ruta)
        do {
            try data.write(to: destino, options: .atomic)
            return ruta
        } catch {
            logger.error("No se pudo escribir la foto en \(destino.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            print("AlmacenFotos.guardar(data): \(error.localizedDescription)")
            throw ErrorAlmacenFotos.noSePudoEscribirElArchivo
        }
    }

    // MARK: - Leer

    /// Lee una imagen desde su ruta relativa. Usa la caché de disco.
    func imagen(paraRuta ruta: String) -> CGImage? {
        guard let datos = datos(paraRuta: ruta) else { return nil }
        guard let fuente = CGImageSourceCreateWithData(datos as CFData, nil) else {
            logger.error("No se pudo decodificar la imagen \(ruta, privacy: .public)")
            return nil
        }
        let opciones: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true]
        guard let imagen = CGImageSourceCreateImageAtIndex(fuente, 0, opciones as CFDictionary) else {
            logger.error("No se pudo crear el CGImage de \(ruta, privacy: .public)")
            return nil
        }
        return imagen
    }

    /// Devuelve los bytes del archivo (con caché en memoria).
    func datos(paraRuta ruta: String) -> Data? {
        if let enCache = cache.object(forKey: ruta as NSString) {
            return enCache as Data
        }
        let archivo = url(paraRuta: ruta)
        guard fm.fileExists(atPath: archivo.path) else { return nil }
        guard let datos = try? Data(contentsOf: archivo) else {
            logger.error("No se pudo leer el archivo \(ruta, privacy: .public)")
            return nil
        }
        cache.setObject(datos as NSData, forKey: ruta as NSString)
        return datos
    }

    // MARK: - Borrar

    /// Borra el archivo de una foto (si existe).
    func borrar(ruta: String) {
        cache.removeObject(forKey: ruta as NSString)
        let archivo = url(paraRuta: ruta)
        guard fm.fileExists(atPath: archivo.path) else { return }
        do {
            try fm.removeItem(at: archivo)
        } catch {
            logger.error("No se pudo borrar \(ruta, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Borra todas las fotos de la app (y vacía la caché).
    func borrarTodasLasFotos() {
        cache.removeAllObjects()
        let contenido = (try? fm.contentsOfDirectory(at: carpetaFotos,
                                                     includingPropertiesForKeys: nil,
                                                     options: [.skipsHiddenFiles])) ?? []
        for url in contenido where url.hasDirectoryPath == false {
            try? fm.removeItem(at: url)
        }
    }

    // MARK: - Métricas

    /// Espacio ocupado por las fotos, en bytes.
    func espacioUsado() -> Int64 {
        let contenido = (try? fm.contentsOfDirectory(at: carpetaFotos,
                                                     includingPropertiesForKeys: [.fileSizeKey],
                                                     options: [.skipsHiddenFiles])) ?? []
        var total: Int64 = 0
        for url in contenido {
            let valores = try? url.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(valores?.fileSize ?? 0)
        }
        return total
    }

    /// Todas las fotos guardadas, como rutas relativas ordenadas (`Fotos/abc.jpg`).
    func todasLasFotos() -> [String] {
        let contenido = (try? fm.contentsOfDirectory(at: carpetaFotos,
                                                     includingPropertiesForKeys: nil,
                                                     options: [.skipsHiddenFiles])) ?? []
        return contenido
            .filter { $0.hasDirectoryPath == false }
            .map { "Fotos/\($0.lastPathComponent)" }
            .sorted()
    }

    // MARK: - Utilidades

    /// Codifica un CGImage a JPEG en memoria.
    static func codificarJPEG(_ imagen: CGImage, calidad: Double) -> Data? {
        let datos = NSMutableData()
        guard let destino = CGImageDestinationCreateWithData(datos,
                                                             UTType.jpeg.identifier as CFString,
                                                             1,
                                                             nil) else { return nil }
        let propiedades: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: calidad
        ]
        CGImageDestinationAddImage(destino, imagen, propiedades as CFDictionary)
        guard CGImageDestinationFinalize(destino) else { return nil }
        return datos as Data
    }
}
