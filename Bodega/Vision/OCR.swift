import Foundation
import Vision
import CoreImage
import CoreGraphics
import ImageIO

/// Reconocimiento de etiquetas con Vision (100 % local: sin red, sin UIKit, sin modelos externos).
///
/// Qué extrae de una foto de botella:
/// - texto completo y líneas de la etiqueta,
/// - volumen en mililitros,
/// - graduación alcohólica,
/// - código de barras impreso en la etiqueta,
/// - marca y nombre del producto (heurística por palabras clave).
///
/// La parte "inteligente" (`parsear`) es una función pura y testeable sin cámara.
enum LectorOCR {

    // MARK: - Marcas conocidas (heurística de marca)

    /// Puente opcional con otra fuente de marcas. No hace falta conectarlo:
    /// `Catalogo.marcasConocidas` ya está en el módulo. Se deja por si algún día
    /// la lista se carga de otro sitio.
    static var resolutorMarcasConocidas: (() -> [String])?

    /// Marcas extra que se pueden sumar en runtime.
    static var marcasConocidasExtra: [String] = []

    /// Lista local de respaldo (20 marcas frecuentes). Complementa a `Catalogo.marcasConocidas`
    /// para que la heurística siga funcionando aunque el catálogo cambie.
    static let marcasConocidasRespaldo: [String] = [
        "Santa Ana", "Torres", "Chandon", "Freixenet", "Cruzcampo", "Malfy",
        "Concha y Toro", "Santa Ema", "Trapiche", "Luigi Bosca",
        "Cavit", "Fetzer", "Norton", "Barefoot", "Undurraga",
        "Cono Sur", "Errázuriz", "Graffigna", "Santa Rita", "Navarro Correas"
    ]

    /// Todas las marcas que conoce el lector: catálogo + respaldo + extras.
    static var marcasConocidas: [String] {
        var lista = Catalogo.marcasConocidas
        lista += marcasConocidasRespaldo
        if let resuelta = resolutorMarcasConocidas { lista += resuelta() }
        lista += marcasConocidasExtra

        // Sin duplicados (gana la primera aparición, que es la del catálogo).
        var vistas = Set<String>()
        return lista.filter { marca in
            let clave = Unidades.normaliza(marca)
            guard !clave.isEmpty else { return false }
            return vistas.insert(clave).inserted
        }
    }

    // MARK: - Lectura con Vision

    /// Reconoce el texto de la etiqueta de una imagen. Devuelve siempre una lectura:
    /// si no reconoce nada, devuelve una `LecturaEtiqueta` vacía.
    static func leer(_ imagen: CGImage) async -> LecturaEtiqueta {
        let lineas = await reconocerLineas(imagen)
        return parsear(lineas.joined(separator: "\n"))
    }

    /// Ejecuta el pedido de Vision fuera del hilo principal y devuelve las líneas en orden de lectura.
    private static func reconocerLineas(_ imagen: CGImage) async -> [String] {
        let observaciones: [VNRecognizedTextObservation] = await withCheckedContinuation { continuacion in
            DispatchQueue.global(qos: .userInitiated).async {
                // Los objetos de Vision se crean dentro del bloque para no compartir estado entre hilos.
                let solicitud = VNRecognizeTextRequest()
                solicitud.recognitionLevel = .accurate
                solicitud.recognitionLanguages = ["es-ES", "en-US"]
                solicitud.usesLanguageCorrection = true

                let manejador = VNImageRequestHandler(cgImage: imagen, options: [:])
                do {
                    try manejador.perform([solicitud])
                } catch {
                    // Si Vision falla, seguimos con lo que haya (posiblemente vacío).
                }
                let resultados = solicitud.results ?? []
                continuacion.resume(returning: resultados)
            }
        }

        // Orden de lectura: de arriba hacia abajo y, en la misma banda, de izquierda a derecha.
        let ordenadas = observaciones.sorted { a, b in
            let diferenciaY = a.boundingBox.midY - b.boundingBox.midY
            if abs(diferenciaY) > 0.02 { return diferenciaY > 0 }
            return a.boundingBox.minX < b.boundingBox.minX
        }

        return ordenadas
            .compactMap { $0.topCandidates(1).first?.string }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Parseo puro (testeable)

    /// Convierte texto plano de etiqueta en datos estructurados. Función pura: no usa Vision.
    static func parsear(_ texto: String) -> LecturaEtiqueta {
        let lineas = texto
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let textoCompleto = lineas.joined(separator: " ")
        let marca = detectarMarca(lineas: lineas)

        return LecturaEtiqueta(
            textoCompleto: textoCompleto,
            lineas: lineas,
            marca: marca,
            nombre: detectarNombre(lineas: lineas, marca: marca),
            volumenML: Unidades.mililitros(texto: textoCompleto),
            graduacion: detectarGraduacion(lineas: lineas),
            codigoBarras: detectarCodigoBarras(texto: textoCompleto)
        )
    }

    // MARK: - Código de barras impreso en la etiqueta

    /// Busca un número de 8, 12, 13 o 14 dígitos (EAN-8, UPC-A, EAN-13, EAN-14). Prioriza el de 13.
    static func detectarCodigoBarras(texto: String) -> String? {
        let patron = #"(?<!\d)(\d{8}|\d{12}|\d{13}|\d{14})(?!\d)"#
        guard let regex = try? NSRegularExpression(pattern: patron) else { return nil }
        let rango = NSRange(texto.startIndex..., in: texto)

        var encontrados: [String] = []
        for coincidencia in regex.matches(in: texto, options: [], range: rango) {
            guard let rangoCodigo = Range(coincidencia.range, in: texto) else { continue }
            encontrados.append(String(texto[rangoCodigo]))
        }

        for longitud in [13, 14, 12, 8] {
            if let codigo = encontrados.first(where: { $0.count == longitud }) { return codigo }
        }
        return nil
    }

    // MARK: - Graduación

    /// `Unidades.graduacion` mira hacia adelante un trozo de texto, así que en una etiqueta
    /// con volumen y grado ("750 ml 13,5 % vol") puede engancharse al volumen.
    /// Por eso limpiamos los volúmenes de cada línea antes de preguntar.
    private static func detectarGraduacion(lineas: [String]) -> Double? {
        for linea in lineas {
            let sinVolumenes = quitaVolumenes(linea)
            if let valor = Unidades.graduacion(texto: sinVolumenes) { return valor }
            if let valor = Unidades.graduacion(texto: linea) { return valor }
        }
        return nil
    }

    // MARK: - Marca

    /// Heurística de marca: marca conocida → línea en mayúsculas → línea más corta útil.
    static func detectarMarca(lineas: [String]) -> String? {
        let indiceNombre = indiceMejorNombre(lineas: lineas)
        let candidatas = lineas.enumerated().filter { _, linea in
            !esLineaDeDatos(linea) && linea.contains(where: { $0.isLetter })
        }
        guard !candidatas.isEmpty else { return nil }

        // 1) Marca conocida: la señal más fiable.
        for (_, linea) in candidatas {
            let tokens = Unidades.normaliza(linea).split(separator: " ").map(String.init)
            guard !tokens.isEmpty else { continue }
            for marca in marcasConocidas {
                let tokensMarca = Unidades.normaliza(marca).split(separator: " ").map(String.init)
                guard !tokensMarca.isEmpty else { continue }
                // Comparación por palabras completas: "Burn" no debe aparecer dentro de "Burton".
                if contieneSecuencia(tokens, tokensMarca) { return limpiaMarca(marca) }
            }
        }

        // 2) Primera línea claramente en mayúsculas (así llegan los logotipos al OCR).
        for (indice, linea) in candidatas {
            guard esMayuscula(linea), linea.count <= 30 else { continue }
            let candidata = marcaDeLinea(linea)
            // Si la línea es solo el tipo ("GIN"), no sirve como marca.
            guard Unidades.normaliza(candidata).count >= 2 else { continue }
            // Si además es la mejor descripción de producto, se deja para el nombre.
            if indice == indiceNombre, Unidades.normaliza(candidata) == Unidades.normaliza(linea) { continue }
            let limpia = limpiaMarca(candidata)
            if !limpia.isEmpty { return limpia }
        }

        // 3) La línea más corta que no sea un dato ni el nombre del producto.
        let cortas = candidatas.filter { $0.0 != indiceNombre && $0.1.count <= 24 }
        if let elegida = cortas.min(by: { $0.1.count < $1.1.count }) {
            let limpia = limpiaMarca(elegida.1)
            if !limpia.isEmpty { return limpia }
        }

        return nil
    }

    // MARK: - Nombre del producto

    /// Nombre del producto: la línea con más "información de producto" que no sea marca ni dato.
    /// - Parameter marca: la marca ya detectada (si se pasa nil, se detecta aquí).
    static func detectarNombre(lineas: [String], marca: String? = nil) -> String? {
        let marcaDetectada = marca ?? detectarMarca(lineas: lineas)
        let tokensMarca = (marcaDetectada.map { Unidades.normaliza($0) } ?? "")
            .split(separator: " ")
            .map(String.init)

        var mejor: (linea: String, puntaje: Double)?
        for linea in lineas {
            if esLineaDeDatos(linea) { continue }
            let norm = Unidades.normaliza(linea)
            guard !norm.isEmpty else { continue }

            // Si la línea es solo la marca (no queda nada más), no puede ser el nombre.
            if !tokensMarca.isEmpty {
                let tokens = norm.split(separator: " ").map(String.init)
                if quitaTokens(tokens, tokensMarca).isEmpty { continue }
            }

            let puntaje = puntajeNombre(linea)
            guard puntaje >= 2 else { continue }
            if mejor == nil || puntaje > mejor!.puntaje { mejor = (linea, puntaje) }
        }

        guard let elegido = mejor else { return nil }
        let limpio = limpiaNombre(elegido.linea)
        return limpio.isEmpty ? nil : limpio
    }

    /// Quita de una lista de palabras la secuencia indicada.
    static func quitaTokens(_ tokens: [String], _ quitar: [String]) -> [String] {
        guard !quitar.isEmpty else { return tokens }
        var resultado = tokens
        var indice = 0
        while indice < resultado.count {
            if indice + quitar.count <= resultado.count,
               Array(resultado[indice..<(indice + quitar.count)]) == quitar {
                resultado.removeSubrange(indice..<(indice + quitar.count))
            } else {
                indice += 1
            }
        }
        return resultado
    }

    /// Índice de la línea que mejor describe el producto.
    private static func indiceMejorNombre(lineas: [String]) -> Int? {
        var mejorIndice: Int?
        var mejorPuntaje = 0.0
        for (indice, linea) in lineas.enumerated() {
            let puntaje = puntajeNombre(linea)
            if puntaje >= 2, puntaje > mejorPuntaje {
                mejorPuntaje = puntaje
                mejorIndice = indice
            }
        }
        return mejorIndice
    }

    // MARK: - Utilidades de texto

    /// Puntúa una línea según parece describir un producto (uva, tipo, modificador, palabras).
    static func puntajeNombre(_ linea: String) -> Double {
        let norm = Unidades.normaliza(linea)
        guard !norm.isEmpty else { return 0 }
        if esLineaDeDatos(linea) { return 0 }

        var puntos = 0.0
        if palabrasVarietal.contains(where: { norm.contains($0) }) { puntos += 3 }
        if palabrasTipo.contains(where: { norm.contains($0) }) { puntos += 2 }
        if palabrasModificador.contains(where: { norm.contains($0) }) { puntos += 1.5 }

        let cantidad = norm.split(separator: " ").count
        if cantidad >= 2 { puntos += 0.5 }
        if cantidad >= 3 { puntos += 0.5 }

        if norm.contains("cont net") || norm.contains("contenido") || norm.contains("net content") { puntos -= 3 }
        if norm.contains("elaborado") || norm.contains("producto de") || norm.contains("botella de") { puntos -= 1 }
        if norm.contains("industria") || norm.contains("embotellado") { puntos -= 2 }

        return puntos
    }

    /// true si la secuencia de palabras del patrón aparece (entera y en orden) en el texto.
    static func contieneSecuencia(_ texto: [String], _ patron: [String]) -> Bool {
        guard !texto.isEmpty, !patron.isEmpty, patron.count <= texto.count else { return false }
        for inicio in 0...(texto.count - patron.count) {
            if Array(texto[inicio..<(inicio + patron.count)]) == patron { return true }
        }
        return false
    }

    /// Si una línea mezcla marca y tipo ("BARTON'S GIN"), la marca es lo que va antes del tipo.
    static func marcaDeLinea(_ linea: String) -> String {
        let palabras = linea.split(separator: " ").map(String.init)
        for (indice, palabra) in palabras.enumerated() {
            let norm = Unidades.normaliza(palabra)
            guard !norm.isEmpty, tiposExactos.contains(norm) else { continue }
            let antes = palabras.prefix(indice).joined(separator: " ")
            return antes.isEmpty ? linea : antes
        }
        return linea
    }

    /// Quita sufijos corporativos de una marca ("S.L.", "S.A.", "Bodegas", "S.L.U."...).
    static func limpiaMarca(_ texto: String) -> String {
        let tokens = texto
            .replacingOccurrences(of: #"[^A-Za-zÀ-ÿ0-9Ññ&.']"#, with: " ", options: .regularExpression)
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)

        var conservados: [String] = []
        for token in tokens {
            let norm = Unidades.normaliza(token)
            guard !norm.isEmpty else { continue }
            let compacto = norm.replacingOccurrences(of: " ", with: "")
            if sufijosMarca.contains(norm) || sufijosMarca.contains(compacto) { continue }
            let limpio = token.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
            if !limpio.isEmpty { conservados.append(limpio) }
        }

        let resultado = conservados.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return resultado.isEmpty ? texto.trimmingCharacters(in: .whitespacesAndNewlines) : resultado
    }

    /// Limpia un nombre de producto (quita el volumen y la puntuación sobrante).
    static func limpiaNombre(_ texto: String) -> String {
        var resultado = quitaVolumenes(texto)
        resultado = resultado.trimmingCharacters(in: CharacterSet(charactersIn: " .,;:-–—"))
        return resultado.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Elimina del texto las menciones de volumen ("750 ml", "0,75 L"...).
    static func quitaVolumenes(_ texto: String) -> String {
        let patron = #"\d{1,4}(?:[.,]\d{1,3})?\s*(ml|mililitros?|cc|cl|l|litros?)\b"#
        guard let regex = try? NSRegularExpression(pattern: patron, options: [.caseInsensitive]) else { return texto }
        let rango = NSRange(texto.startIndex..., in: texto)
        return regex.stringByReplacingMatches(in: texto, options: [], range: rango, withTemplate: " ")
    }

    /// true si la línea es solo un dato (volumen, graduación o número suelto).
    static func esLineaDeDatos(_ linea: String) -> Bool {
        let norm = Unidades.normaliza(linea)
        if norm.isEmpty { return true }
        if esSoloNumero(linea) { return true }
        if coincideCompleto(patronVolumenSolo, linea) { return true }
        if coincideCompleto(patronGradoSolo, linea) { return true }
        return false
    }

    /// true si la línea está escrita casi por completo en mayúsculas.
    static func esMayuscula(_ linea: String) -> Bool {
        let letras = linea.filter { $0.isLetter }
        guard letras.count >= 3 else { return false }
        let mayusculas = letras.filter { $0.isUppercase }.count
        return Double(mayusculas) / Double(letras.count) >= 0.7
    }

    private static func esSoloNumero(_ linea: String) -> Bool {
        let digitos = linea.filter { $0.isNumber }
        let otros = linea.filter { !$0.isNumber && !$0.isWhitespace && $0 != "." && $0 != "," && $0 != "-" }
        return !digitos.isEmpty && otros.isEmpty
    }

    private static func coincideCompleto(_ patron: String, _ texto: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: patron, options: [.caseInsensitive]) else { return false }
        let rango = NSRange(texto.startIndex..., in: texto)
        guard let coincidencia = regex.firstMatch(in: texto, options: [], range: rango) else { return false }
        return coincidencia.range == rango
    }

    // MARK: - Listas de palabras

    private static let patronVolumenSolo = #"^\s*\d{1,4}(?:[.,]\d{1,3})?\s*(ml|mililitros?|cc|cl|l|litros?)\s*$"#
    private static let patronGradoSolo = #"^\s*\d{1,2}(?:[.,]\d)?\s*%(\s*(vol\.?|abv|alc\.?|alcohol))?\s*$"#

    private static let sufijosMarca: Set<String> = [
        "s", "a", "u", "sl", "sa", "sas", "slu", "srl", "sa de cv", "s de rl de c v",
        "ltda", "ltd", "inc", "corp", "co", "company", "bodega", "bodegas"
    ]

    private static let palabrasVarietal = [
        "malbec", "cabernet", "sauvignon", "chardonnay", "merlot", "syrah", "shiraz",
        "pinot", "tempranillo", "graciano", "garnacha", "carignan", "malvasia",
        "riesling", "verdot", "tannat", "carmenere", "petit verdot"
    ]

    private static let palabrasTipo = [
        "vino", "tinto", "blanco", "rosado", "espumoso", "espumante", "cava", "prosecco",
        "brut", "champan", "champagne", "sherry", "moscatel", "whisky", "whiskey", "ron",
        "tequila", "vodka", "gin", "aperitivo", "vermut", "conac", "cognac", "brandy",
        "licor", "sake", "calvados", "grappa", "chartreuse", "anis", "orujo"
    ]

    private static let palabrasModificador = [
        "reserva", "gran reserva", "anejo", "extra", "especial", "seleccion", "premium",
        "gold", "doble", "dry", "secco", "limitado", "crianza", "vendimia", "nuevo"
    ]

    /// Tipos exactos (una sola palabra) para separar marca y tipo en una misma línea.
    private static let tiposExactos: Set<String> = [
        "vino", "tinto", "blanco", "rosado", "espumoso", "espumante", "cava", "prosecco",
        "brut", "champan", "champagne", "sherry", "moscatel", "whisky", "whiskey", "ron",
        "tequila", "vodka", "gin", "aperitivo", "vermut", "conac", "cognac", "brandy",
        "licor", "sake", "calvados", "grappa", "chartreuse", "anis", "orujo"
    ]
}
