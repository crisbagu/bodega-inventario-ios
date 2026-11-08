import Foundation
import CoreImage
import CoreGraphics
import ImageIO

/// Análisis del color de la botella con Core Image (offline, sin UIKit).
///
/// Sirve como pista débil: ayuda a desempatar cuando el texto no alcanza,
/// pero nunca identifica por sí solo.
enum AnalizadorColor {

    /// Color dominante de la zona central de la imagen (los bordes son el fondo de la foto).
    /// Devuelve "#RRGGBB" en mayúsculas o `nil` si no se puede calcular.
    static func dominante(_ imagen: CGImage) -> String? {
        let ancho = imagen.width
        let alto = imagen.height
        guard ancho > 0, alto > 0 else { return nil }

        // Recorte central: quitamos el 20 % de cada lado (normalmente el fondo de la mesa).
        let margenX = Double(ancho) * 0.2
        let margenY = Double(alto) * 0.2
        var rect = CGRect(x: margenX, y: margenY,
                          width: Double(ancho) - 2 * margenX,
                          height: Double(alto) - 2 * margenY)
        if rect.width < 2 || rect.height < 2 {
            rect = CGRect(x: 0, y: 0, width: Double(ancho), height: Double(alto))
        }

        guard let rgb = colorCentral(imagen: imagen, rect: rect) else { return nil }
        return textoHex(r: rgb.0, g: rgb.1, b: rgb.2)
    }

    /// Similitud entre dos colores hex (#RRGGBB). Devuelve 0...1 (0 si alguno es nil).
    ///
    /// Trabaja en HSB: dos tonos cercanos valen más que dos colores con la misma
    /// luminosidad pero tonos distintos. Negro y blanco puros no sirven para comparar.
    static func similitud(_ hexA: String?, _ hexB: String?) -> Double {
        guard let hexA, let hexB else { return 0 }
        guard let a = componentes(hexA), let b = componentes(hexB) else { return 0 }

        // Mismo color exacto.
        if hexNormalizado(hexA) == hexNormalizado(hexB) { return 1 }

        let hsbA = hsb(r: a.r, g: a.g, b: a.b)
        let hsbB = hsb(r: b.r, g: b.g, b: b.b)

        // Negro o blanco puros: el color real no es fiable, no aporta nada.
        if esNegroOPuro(hsbA) || esNegroOPuro(hsbB) { return 0 }
        if esBlancoOPuro(hsbA) || esBlancoOPuro(hsbB) { return 0 }

        let diferenciaTonal = distanciaTonal(hsbA.h, hsbB.h)
        let diferenciaSaturacion = abs(hsbA.s - hsbB.s)
        let diferenciaLuminosidad = abs(hsbA.b - hsbB.b)

        let distancia = (0.75 * diferenciaTonal * diferenciaTonal
                         + 0.15 * diferenciaSaturacion * diferenciaSaturacion
                         + 0.10 * diferenciaLuminosidad * diferenciaLuminosidad).squareRoot()

        let similitud = 1 - distancia
        return max(0, min(1, similitud * similitud))
    }

    // MARK: - Cálculo del color central

    /// Promedio de color de una zona de la imagen (primero Core Image, con respaldo en Core Graphics).
    private static func colorCentral(imagen: CGImage, rect: CGRect) -> (Double, Double, Double)? {
        if let color = colorCentralCoreImage(imagen: imagen, rect: rect) { return color }
        return colorCentralCoreGraphics(imagen: imagen, rect: rect)
    }

    /// CIAreaAverage sobre la zona recortada.
    private static func colorCentralCoreImage(imagen: CGImage, rect: CGRect) -> (Double, Double, Double)? {
        let ciImagen = CIImage(cgImage: imagen)
        let recortada = ciImagen.cropped(to: rect)
        guard recortada.extent.width >= 1, recortada.extent.height >= 1 else { return nil }

        guard let filtro = CIFilter(name: "CIAreaAverage") else { return nil }
        filtro.setValue(recortada, forKey: kCIInputImageKey)
        filtro.setValue(CIVector(cgRect: recortada.extent), forKey: kCIInputExtentKey)
        guard let salida = filtro.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        let contexto = CIContext()
        contexto.render(salida,
                        toBitmap: &pixel,
                        rowBytes: 4,
                        bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                        format: .RGBA8,
                        colorSpace: CGColorSpaceCreateDeviceRGB())

        // Si la salida es totalmente transparente, Core Image no pudo promediar.
        if pixel[3] == 0 { return nil }
        return (Double(pixel[0]) / 255.0, Double(pixel[1]) / 255.0, Double(pixel[2]) / 255.0)
    }

    /// Respaldo: dibujamos la zona recortada en un contexto de 1x1 píxel.
    private static func colorCentralCoreGraphics(imagen: CGImage, rect: CGRect) -> (Double, Double, Double)? {
        guard let recortada = imagen.cropping(to: rect) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)

        let dibujado = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let contexto = CGContext(data: base,
                                           width: 1,
                                           height: 1,
                                           bitsPerComponent: 8,
                                           bytesPerRow: 4,
                                           space: CGColorSpaceCreateDeviceRGB(),
                                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            contexto.interpolationQuality = .medium
            contexto.draw(recortada, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard dibujado else { return nil }

        return (Double(pixel[0]) / 255.0, Double(pixel[1]) / 255.0, Double(pixel[2]) / 255.0)
    }

    // MARK: - Conversiones

    /// "#RRGGBB" (o "RRGGBB") → componentes 0...1.
    private static func componentes(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        let limpio = hexNormalizado(hex)
        guard limpio.count == 6, let valor = UInt32(limpio, radix: 16) else { return nil }
        let r = Double((valor >> 16) & 0xFF) / 255.0
        let g = Double((valor >> 8) & 0xFF) / 255.0
        let b = Double(valor & 0xFF) / 255.0
        return (r, g, b)
    }

    /// Normaliza a mayúsculas sin "#" y con 6 dígitos.
    private static func hexNormalizado(_ hex: String) -> String {
        var limpio = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if limpio.hasPrefix("#") { limpio.removeFirst() }
        if limpio.count == 8 { limpio = String(limpio.prefix(6)) } // ignora alfa
        return limpio
    }

    /// "#RRGGBB" en mayúsculas.
    private static func textoHex(r: Double, g: Double, b: Double) -> String {
        func canal(_ valor: Double) -> Int {
            let v = max(0, min(255, Int((valor * 255).rounded())))
            return v
        }
        return String(format: "#%02X%02X%02X", canal(r), canal(g), canal(b))
    }

    /// Componentes en HSB (tono 0...1, saturación 0...1, luminosidad 0...1).
    private struct ColorHSB {
        var h: Double
        var s: Double
        var b: Double
    }

    private static func hsb(r: Double, g: Double, b: Double) -> ColorHSB {
        let maximo = max(r, max(g, b))
        let minimo = min(r, min(g, b))
        let delta = maximo - minimo

        var tono = 0.0
        if delta > 0 {
            if maximo == r {
                tono = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maximo == g {
                tono = ((b - r) / delta) + 2
            } else {
                tono = ((r - g) / delta) + 4
            }
            if tono < 0 { tono += 6 }
            tono /= 6
        }

        let saturacion = maximo == 0 ? 0 : delta / maximo
        return ColorHSB(h: tono, s: saturacion, b: maximo)
    }

    /// Distancia de tono circular (0...1): dos tonos a 0° y 180° están lejos.
    private static func distanciaTonal(_ a: Double, _ b: Double) -> Double {
        let diferencia = abs(a - b)
        let circular = min(diferencia, 1 - diferencia)
        return circular * 2 // 0...1 (1 = tonos opuestos)
    }

    private static func esNegroOPuro(_ color: ColorHSB) -> Bool {
        color.b < 0.10 && color.s < 0.20
    }

    private static func esBlancoOPuro(_ color: ColorHSB) -> Bool {
        color.b > 0.93 && color.s < 0.15
    }
}
