import Foundation
import Vision
import CoreImage
import CoreGraphics
import ImageIO

/// Detección de códigos de barras con Vision (offline, sin UIKit).
///
/// Es la fuente más exacta de identificación: si el código coincide con el de una
/// variante guardada, esa variante gana con una confianza muy por encima del resto.
enum LectorBarras {

    /// Simtofonías soportadas, en orden de preferencia para el sector de licores.
    static let simbolos: [VNBarcodeSymbology] = [
        .ean13, .upce, .ean8, .code128, .code39, .itf14, .qr
    ]

    /// Devuelve el payload del primer código de barras detectado (EAN-13/UPC primero).
    /// `nil` si la imagen no tiene un código legible.
    static func codigo(_ imagen: CGImage) async -> String? {
        let observaciones: [VNBarcodeObservation] = await withCheckedContinuation { continuacion in
            DispatchQueue.global(qos: .userInitiated).async {
                // Los objetos de Vision se crean dentro del bloque para no compartir estado entre hilos.
                let solicitud = VNDetectBarcodesRequest()
                solicitud.symbologies = simbolos

                let manejador = VNImageRequestHandler(cgImage: imagen, options: [:])
                do {
                    try manejador.perform([solicitud])
                } catch {
                    // Sin detecciones: devolvemos lista vacía.
                }
                let resultados = solicitud.results ?? []
                continuacion.resume(returning: resultados)
            }
        }

        let utiles = observaciones.compactMap { observacion -> (String, VNBarcodeSymbology)? in
            guard let payload = observacion.payloadStringValue else { return nil }
            let limpio = payload.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !limpio.isEmpty else { return nil }
            return (limpio, observacion.symbology)
        }
        guard !utiles.isEmpty else { return nil }

        // Prioriza EAN-13 y UPC: son los de las botellas.
        let ordenadas = utiles.sorted { a, b in
            let pesoA = prioridad(a.1)
            let pesoB = prioridad(b.1)
            if pesoA != pesoB { return pesoA < pesoB }
            return a.0.count > b.0.count
        }

        return ordenadas.first?.0
    }

    /// Orden de preferencia: EAN-13, UPC-E, EAN-8, ITF-14, Code-128, Code-39, QR.
    private static func prioridad(_ simbolo: VNBarcodeSymbology) -> Int {
        switch simbolo {
        case .ean13: return 0
        case .upce: return 1
        case .ean8: return 2
        case .itf14: return 3
        case .code128: return 4
        case .code39: return 5
        case .qr: return 6
        default: return 7
        }
    }
}
