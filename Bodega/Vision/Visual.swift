import Foundation
import Vision
import CoreImage

/// Comparación visual de la foto nueva contra las fotos de referencia ya guardadas.
///
/// Usa `VNFeaturePrint` (Vision, en el dispositivo): convierte cada imagen en una
/// "huella" de características y mide la distancia entre huellas. Distancia 0 = misma
/// botella; cuanto mayor, menos se parecen. Sin internet y sin modelos externos.
///
/// Nota: `VNComputeImageFeaturePrintDistanceRequest` solo existe en iOS, así que en
/// macOS (arnés de verificación) la comparación visual queda desactivada.
enum MotorVisual {

    /// Distancia a partir de la cual consideramos que dos botellas NO son el mismo producto.
    static let distanciaMaxima: Float = 18.0

#if os(iOS)
    /// Huella visual de una imagen.
    static func huella(_ imagen: CGImage) throws -> VNFeaturePrintObservation {
        let solicitud = VNGenerateImageFeaturePrintRequest()
        let manejador = VNImageRequestHandler(cgImage: imagen, options: [:])
        try manejador.perform([solicitud])
        guard let observacion = solicitud.results?.first as? VNFeaturePrintObservation else {
            throw MotorVisualError.sinHuella
        }
        return observacion
    }

    /// Distancia entre dos huellas (0 = idénticas).
    static func distancia(_ a: VNFeaturePrintObservation, _ b: VNFeaturePrintObservation) throws -> Float {
        var distancia: Float = 0
        let solicitud = VNComputeImageFeaturePrintDistanceRequest()
        try solicitud.computeDistance(&distancia, between: a, and: b)
        return distancia
    }

    /// Distancia entre dos imágenes (nil en plataformas sin soporte).
    static func distancia(_ imagenA: CGImage, _ imagenB: CGImage) -> Float? {
        guard let huellaA = try? huella(imagenA),
              let huellaB = try? huella(imagenB),
              let d = try? distancia(huellaA, huellaB) else { return nil }
        return d
    }
#else
    /// En macOS no hay API de distancia entre huellas: se devuelve nil.
    static func distancia(_ imagenA: CGImage, _ imagenB: CGImage) -> Float? { nil }
#endif

    /// Similitud 0...1 a partir de una distancia de Vision (1 = idénticas).
    static func similitud(distancia: Float) -> Double {
        let normalizada = max(0, min(1, 1 - Double(distancia) / Double(distanciaMaxima)))
        return normalizada
    }

    /// Compara la foto nueva contra varias fotos de referencia.
    /// - Returns: ruta de referencia -> similitud 0...1 (solo las que superaron `umbral`).
    static func similitudes(contra imagen: CGImage,
                            referencias: [String],
                            leerImagen: (String) -> CGImage?,
                            umbral: Double = 0.45) -> [String: Double] {
        guard !referencias.isEmpty else { return [:] }
        var salida: [String: Double] = [:]
        for ruta in referencias {
            guard let referencia = leerImagen(ruta) else { continue }
            guard let d = distancia(imagen, referencia) else { continue }
            let similitud = similitud(distancia: d)
            if similitud >= umbral { salida[ruta] = similitud }
        }
        return salida
    }

    /// Mejor similitud (0...1) entre la foto nueva y un conjunto de referencias.
    static func mejorSimilitud(contra imagen: CGImage,
                               referencias: [String],
                               leerImagen: (String) -> CGImage?) -> Double {
        similitudes(contra: imagen, referencias: referencias, leerImagen: leerImagen).values.max() ?? 0
    }

    enum MotorVisualError: Error {
        case sinHuella
    }
}
