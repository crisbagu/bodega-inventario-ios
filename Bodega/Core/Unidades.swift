import Foundation

/// Conversión y formato de volúmenes. Internamente todo se guarda en mililitros.
enum Unidades {

    // MARK: - Parseo

    /// Extrae el volumen en mililitros de un texto de etiqueta.
    /// Acepta: "750 ml", "750ml", "0,75 L", "1 L", "1.5 L", "375 cc", "50 cl".
    static func mililitros(texto: String) -> Int? {
        guard !texto.isEmpty else { return nil }
        let patrones = [
            #"(\d{1,4}(?:[.,]\d{1,3})?)\s*(ml|mililitros?|cc|cl|l|litros?)\b"#,
            #"\b(l|litros?)\s*(\d{1,4}(?:[.,]\d{1,3})?)"#
        ]
        var mejor: Int?
        for patron in patrones {
            guard let regex = try? NSRegularExpression(pattern: patron, options: [.caseInsensitive]) else { continue }
            let rango = NSRange(texto.startIndex..., in: texto)
            for coincidencia in regex.matches(in: texto, options: [], range: rango) {
                guard coincidencia.numberOfRanges >= 3 else { continue }
                let rangoNumero = coincidencia.range(at: 1)
                let rangoUnidad = coincidencia.range(at: 2)
                guard let rN = Range(rangoNumero, in: texto), let rU = Range(rangoUnidad, in: texto) else { continue }
                let numeroTexto = texto[rN].replacingOccurrences(of: ",", with: ".")
                guard let numero = Double(numeroTexto) else { continue }
                let unidad = texto[rU].lowercased()
                var ml: Double?
                switch unidad {
                case "ml", "mililitro", "mililitros": ml = numero
                case "cc": ml = numero
                case "cl": ml = numero * 10
                case "l", "litro", "litros": ml = numero * 1000
                default: ml = nil
                }
                guard let valor = ml, valor > 0, valor <= 20000 else { continue }
                let entero = Int(valor.rounded())
                if mejor == nil || entero > mejor! { mejor = entero }
            }
        }
        return mejor
    }

    /// Extrae el grado alcohólico ("13,5%" | "13.5 % vol" | "40% vol" | "alc. 40").
    /// No confunde el volumen ("750 ml 13,5 % vol") con el grado: exige que el número
    /// vaya pegado a un "%" o a una palabra clave (vol, alc, alcohol, abv).
    static func graduacion(texto: String) -> Double? {
        guard !texto.isEmpty else { return nil }
        let patrones = [
            #"(?<![\d.,])(\d{1,2}(?:[.,]\d{1,2})?)\s*%"#,
            #"(?<![\d.,])(\d{1,2}(?:[.,]\d{1,2})?)\s*(?:vol\.?|alc\.?|alcohol|abv)(?![a-záéíóúñ])"#,
            #"(?:alc\.?|alcohol|abv)\s*(\d{1,2}(?:[.,]\d{1,2})?)"#
        ]
        for patron in patrones {
            guard let regex = try? NSRegularExpression(pattern: patron, options: [.caseInsensitive]) else { continue }
            let rango = NSRange(texto.startIndex..., in: texto)
            for coincidencia in regex.matches(in: texto, options: [], range: rango) {
                let rangoNumero = coincidencia.range(at: 1)
                guard rangoNumero.location != NSNotFound,
                      let rN = Range(rangoNumero, in: texto) else { continue }
                let numeroTexto = texto[rN].replacingOccurrences(of: ",", with: ".")
                guard let valor = Double(numeroTexto), valor > 0, valor <= 100 else { continue }
                return valor
            }
        }
        return nil
    }

    // MARK: - Formato

    static func litros(_ ml: Int) -> Double { Double(ml) / 1000.0 }

    /// "375 ml"
    static func texto(_ ml: Int) -> String {
        "\(ml) ml"
    }

    /// Formato según la unidad visual elegida: "375 ml" o "0,375 L".
    static func formatea(_ ml: Int, unidad: UnidadVisual) -> String {
        switch unidad {
        case .mililitros:
            return "\(ml) ml"
        case .litros:
            return formateaLitros(Double(ml) / 1000.0)
        }
    }

    /// "375 ml · 0,375 L" — muestra siempre las dos unidades.
    static func formateaLargo(_ ml: Int) -> String {
        "\(ml) ml · \(formateaLitros(Double(ml) / 1000.0))"
    }

    /// Formatea litros con coma decimal (es-ES): 0,375 L
    static func formateaLitros(_ litros: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3
        let numero = formatter.string(from: NSNumber(value: litros)) ?? "\(litros)"
        return "\(numero) L"
    }

    /// Convierte una cantidad expresada en litros a mililitros.
    static func desdeLitros(_ litros: Double) -> Int { Int((litros * 1000).rounded()) }

    /// Normaliza espacios y acentos sueltos para comparar textos de etiquetas.
    static func normaliza(_ texto: String) -> String {
        let minusculas = texto.lowercased()
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "es_ES"))
        return minusculas
            .replacingOccurrences(of: "[^a-z0-9ñ ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Similitud simple entre dos textos (0...1) por palabras compartidas.
    static func similitudTexto(_ a: String, _ b: String) -> Double {
        let na = Set(normaliza(a).split(separator: " ").map(String.init))
        let nb = Set(normaliza(b).split(separator: " ").map(String.init))
        guard !na.isEmpty, !nb.isEmpty else { return 0 }
        let comunes = na.intersection(nb).count
        return Double(comunes) / Double(max(na.count, nb.count))
    }
}
