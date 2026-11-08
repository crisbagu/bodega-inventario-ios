import Foundation

/// Motor de coincidencia: cruza lo leído de la etiqueta con las variantes de la base.
///
/// Prioridad de la evidencia:
/// 1. Código de barras exacto (manda: confianza final ≥ 0,97).
/// 2. Texto de etiqueta (marca, nombre, volumen, graduación, tipo/sabor).
/// 3. Color dominante de la botella (pista débil).
/// 4. Aprendizaje: variantes que antes acertaron suben un poco.
///
/// El resultado siempre es una lista ordenada, con la confianza normalizada a que
/// sume 100 % y el porcentaje listo para pintar en la interfaz.
enum MotorCoincidencia {

    // MARK: - Puentes opcionales

    /// Color dominante conocido por variante (lo puede rellenar el servicio de fotos:
    /// `MotorCoincidencia.coloresPorVariante[id] = "#RRGGGGBB"`).
    static var coloresPorVariante: [UUID: String] = [:]

    /// Puente opcional con `Catalogo.paisProbable` (Bodega/Core/Catalogo.swift).
    /// Conectar en runtime: `MotorCoincidencia.resolutorPais = { Catalogo.paisProbable }`.
    static var resolutorPais: ((String) -> String?)?

    /// Las marcas conocidas viven en `LectorOCR.marcasConocidas` (con su propio puente
    /// a `Catalogo.marcasConocidas`): `LectorOCR.resolutorMarcasConocidas = { Catalogo.marcasConocidas }`.

    // MARK: - Candidatos

    /// Variantes candidatas para una lectura, ordenadas de mayor a menor confianza.
    /// Si ninguna variante encaja pero hay texto leído, devuelve un candidato nuevo (esNuevo = true).
    /// - Parameter similitudesVisuales: parecido visual 0...1 por variante (lo calcula `MotorVisual`).
    static func candidatos(lectura: LecturaEtiqueta,
                           colorHex: String?,
                           variantes: [VarianteInfo],
                           pesos: PesosCoincidencia = PesosCoincidencia(),
                           similitudesVisuales: [UUID: Double] = [:]) -> [CandidatoVariante] {

        var evaluadas: [Evaluada] = []

        for variante in variantes {
            guard !esDescartada(lectura: lectura, variante: variante) else { continue }

            var puntaje = 0.0
            var detalle: [String] = []
            var fuentes: Set<FuenteDeteccion> = []
            var codigoExacto = false

            // 1) Código de barras exacto: la señal más fuerte.
            if let codigo = lectura.codigoBarras,
               let codigoVariante = variante.codigoBarras,
               codigoVariante == codigo {
                puntaje += pesos.codigoBarras
                detalle.append("Código de barras exacto")
                fuentes.insert(.codigoBarras)
                codigoExacto = true
            }

            // 2) Marca.
            if let marca = lectura.marca, !marca.isEmpty, !variante.marca.isEmpty {
                let similitud = Unidades.similitudTexto(marca, variante.marca)
                if similitud >= 0.6 {
                    puntaje += 0.35 * pesos.textoEtiqueta * similitud
                    detalle.append("Marca: \(variante.marca)")
                    fuentes.insert(.textoEtiqueta)
                }
            }

            // 3) Nombre del producto o alguna de sus palabras significativas.
            let puntosNombre = puntosNombre(lectura: lectura, variante: variante, pesos: pesos)
            if puntosNombre > 0 {
                puntaje += puntosNombre
                detalle.append("Nombre: \(variante.nombreProducto)")
                fuentes.insert(.textoEtiqueta)
            }

            // 4) Volumen (si no coincide, la variante ya fue descartada).
            if let volumen = lectura.volumenML, volumen == variante.volumenML {
                puntaje += 0.30 * pesos.textoEtiqueta
                detalle.append("Volumen \(Unidades.texto(volumen))")
                fuentes.insert(.textoEtiqueta)
            }

            // 5) Graduación.
            if let graduacion = lectura.graduacion, variante.graduacion > 0 {
                let diferencia = abs(graduacion - variante.graduacion)
                if diferencia <= 1.5 {
                    puntaje += 0.10
                    detalle.append("Graduación \(formateaGrado(graduacion))")
                    fuentes.insert(.textoEtiqueta)
                }
            }

            // 6) Tipo y sabor (máximo 0,15 en total).
            var extra = 0.0
            let textoNormalizado = Unidades.normaliza(lectura.textoCompleto)
            if !variante.tipo.isEmpty, textoNormalizado.contains(Unidades.normaliza(variante.tipo)) {
                extra += 0.10
                detalle.append("Tipo: \(variante.tipo)")
            }
            if !variante.sabor.isEmpty, textoNormalizado.contains(Unidades.normaliza(variante.sabor)) {
                extra += 0.10
                detalle.append("Sabor: \(variante.sabor)")
            }
            if extra > 0 {
                puntaje += min(extra, 0.15)
                fuentes.insert(.textoEtiqueta)
            }

            // 7) Color de la botella (pista débil, solo si conocemos el color de la variante).
            if let colorHex, let colorVariante = colorConocido(de: variante) {
                let similitud = AnalizadorColor.similitud(colorHex, colorVariante)
                if similitud > 0.5 {
                    puntaje += 0.08 * pesos.colorBotella * similitud
                    detalle.append("Color similar")
                    fuentes.insert(.colorBotella)
                }
            }

            // 8) Parecido visual de la foto (lo aporta `MotorVisual`).
            if let similitud = similitudesVisuales[variante.id], similitud > 0.4 {
                puntaje += 0.30 * pesos.similitudVisual * min(1, similitud)
                detalle.append("Parecido visual")
                fuentes.insert(.similitudVisual)
            }

            // 9) Aprendizaje: lo que antes acertó, sube (nunca baja).
            if variante.intentos > 0 {
                let factor = min(1.15, 1 + 0.15 * variante.tasaAcierto)
                puntaje *= factor
                if variante.aciertos > 0 {
                    detalle.append("\(variante.aciertos) aciertos previos")
                }
            }

            guard puntaje > 0 else { continue }

            evaluadas.append(Evaluada(variante: variante,
                                      puntaje: puntaje,
                                      detalle: detalle,
                                      fuentes: fuentes,
                                      codigoExacto: codigoExacto))
        }

        guard !evaluadas.isEmpty else { return candidatoNuevo(lectura: lectura) }

        let top = Array(evaluadas.sorted { $0.puntaje > $1.puntaje }.prefix(5))
        let confianzas = calcularConfianzas(top)

        var candidatos: [CandidatoVariante] = []
        for (indice, evaluada) in top.enumerated() {
            let variante = evaluada.variante
            let candidato = CandidatoVariante(
                varianteId: variante.id,
                productoId: variante.productoId,
                nombreProducto: variante.nombreProducto,
                marca: variante.marca,
                categoria: variante.categoria,
                volumenML: variante.volumenML,
                tipo: variante.tipo,
                sabor: variante.sabor,
                graduacion: variante.graduacion,
                confianza: confianzas[indice],
                fotoRuta: variante.rutasFotos.first,
                esNuevo: false,
                detalleCoincidencias: evaluada.detalle,
                fuentes: ordenadas(evaluada.fuentes)
            )
            candidatos.append(candidato)
        }

        return candidatos.sorted { $0.confianza > $1.confianza }
    }

    // MARK: - Sugerencias de producto nuevo

    /// Si la lectura trae marca o nombre y ese producto no existe en la base,
    /// propone crearlo.
    static func sugerenciasNuevas(lectura: LecturaEtiqueta, variantes: [VarianteInfo]) -> [SugerenciaNueva] {
        var nombre = (lectura.nombre ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var marca = (lectura.marca ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        // Si la lectura no trae marca ni nombre (p. ej. el usuario solo pegó el texto
        // de la etiqueta), los sacamos del propio texto antes de rendirse.
        if nombre.isEmpty && marca.isEmpty, !lectura.textoCompleto.isEmpty {
            let extraida = LectorOCR.parsear(lectura.textoCompleto)
            nombre = (extraida.nombre ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            marca = (extraida.marca ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !nombre.isEmpty || !marca.isEmpty else { return [] }

        let yaExiste = variantes.contains { variante in
            if !nombre.isEmpty, Unidades.similitudTexto(nombre, variante.nombreProducto) >= 0.6 { return true }
            if !marca.isEmpty, Unidades.similitudTexto(marca, variante.marca) >= 0.6 { return true }
            return false
        }
        guard !yaExiste else { return [] }

        let volumen = lectura.volumenML ?? 750
        let tipo = inferirTipo(texto: lectura.textoCompleto)
        let pais = paisProbable(lectura.textoCompleto)

        return [SugerenciaNueva(nombreProducto: nombre.isEmpty ? "Producto nuevo" : nombre,
                                marca: marca,
                                volumenML: volumen,
                                tipo: tipo,
                                pais: pais,
                                codigoBarras: lectura.codigoBarras)]
    }

    // MARK: - Detalles internos

    /// Estructura auxiliar del cálculo.
    private struct Evaluada {
        var variante: VarianteInfo
        var puntaje: Double
        var detalle: [String]
        var fuentes: Set<FuenteDeteccion>
        var codigoExacto: Bool
    }

    /// Color dominante conocido de una variante: primero el que trae la propia variante
    /// (`VarianteInfo.colorDominante`) y, si no, el que se haya calculado en runtime.
    static func colorConocido(de variante: VarianteInfo) -> String? {
        if let color = variante.colorDominante, !color.isEmpty { return color }
        return coloresPorVariante[variante.id]
    }

    /// Descarta variantes incompatibles con lo leído (volumen o graduación).
    private static func esDescartada(lectura: LecturaEtiqueta, variante: VarianteInfo) -> Bool {
        // Volumen distinto y ambos conocidos: incompatible.
        if let volumen = lectura.volumenML, variante.volumenML > 0, volumen != variante.volumenML {
            return true
        }
        // Graduación muy distinta: incompatible.
        if let graduacion = lectura.graduacion, variante.graduacion > 0 {
            if abs(graduacion - variante.graduacion) > 3 { return true }
        }
        return false
    }

    /// Puntos por nombre de producto (exacto, parecido o palabras sueltas).
    private static func puntosNombre(lectura: LecturaEtiqueta, variante: VarianteInfo, pesos: PesosCoincidencia) -> Double {
        guard !variante.nombreProducto.isEmpty else { return 0 }
        let textoNormalizado = Unidades.normaliza(lectura.textoCompleto)
        guard !textoNormalizado.isEmpty else { return 0 }

        var puntos = 0.0

        // El nombre leído aparece tal cual en el texto.
        if let nombre = lectura.nombre, !nombre.isEmpty {
            let normNombre = Unidades.normaliza(nombre)
            if !normNombre.isEmpty, textoNormalizado.contains(normNombre) {
                puntos = max(puntos, 0.45 * pesos.textoEtiqueta)
            }
            // O se parece mucho al nombre de la variante.
            let similitud = Unidades.similitudTexto(nombre, variante.nombreProducto)
            if similitud >= 0.6 {
                puntos = max(puntos, 0.45 * pesos.textoEtiqueta * similitud)
            }
        }

        // O alguna palabra significativa del producto está en el texto.
        let tokens = tokensSignificativos(variante.nombreProducto)
        if !tokens.isEmpty {
            let encontrados = tokens.filter { textoNormalizado.contains($0) }.count
            if encontrados > 0 {
                let fraccion = Double(encontrados) / Double(tokens.count)
                if fraccion >= 0.5 {
                    puntos = max(puntos, 0.45 * pesos.textoEtiqueta * fraccion)
                }
            }
        }

        return puntos
    }

    /// Palabras con significado de un nombre de producto (ignora palabras genéricas).
    private static func tokensSignificativos(_ nombre: String) -> [String] {
        let genericas: Set<String> = [
            "vino", "tinto", "blanco", "rosado", "espumoso", "espumante", "brut", "reserva",
            "gran", "anejo", "extra", "especial", "premium", "secco", "nuevo", "vinos", "licor",
            "botella", "caja", "pack", "und", "ml", "l"
        ]
        return Unidades.normaliza(nombre)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 4 && !genericas.contains($0) }
    }

    /// Normaliza las confianzas a que sumen 1 y deja el código de barras con ≥ 0,97.
    private static func calcularConfianzas(_ top: [Evaluada]) -> [Double] {
        var confianzas = [Double](repeating: 0, count: top.count)

        if let indiceExacto = top.firstIndex(where: { $0.codigoExacto }) {
            let resto = top.indices.filter { $0 != indiceExacto }
            if resto.isEmpty {
                confianzas[indiceExacto] = 1.0
            } else {
                // El código de barras manda: 0,97 para él y el resto se reparte 0,03.
                confianzas[indiceExacto] = 0.97
                let sumaResto = resto.reduce(0.0) { $0 + top[$1].puntaje }
                for indice in resto {
                    if sumaResto > 0 {
                        confianzas[indice] = 0.03 * top[indice].puntaje / sumaResto
                    } else {
                        confianzas[indice] = 0.03 / Double(resto.count)
                    }
                }
            }
        } else {
            let suma = top.reduce(0.0) { $0 + $1.puntaje }
            if suma > 0 {
                for indice in top.indices {
                    confianzas[indice] = top[indice].puntaje / suma
                }
            } else {
                for indice in top.indices {
                    confianzas[indice] = 1.0 / Double(top.count)
                }
            }
        }

        // Redondeo a 3 decimales y ajuste de la mayor para que la suma sea 1,0.
        var finales = confianzas.map { (($0 * 1000).rounded()) / 1000 }
        let total = finales.reduce(0, +)
        if let indiceMayor = finales.indices.max(by: { finales[$0] < finales[$1] }) {
            let ajustado = (finales[indiceMayor] + (1.0 - total)) * 1000
            finales[indiceMayor] = min(1.0, max(0.0, (ajustado).rounded() / 1000))
        }
        return finales
    }

    /// Candidato "producto nuevo" cuando nada encaja pero se leyó texto.
    private static func candidatoNuevo(lectura: LecturaEtiqueta) -> [CandidatoVariante] {
        let texto = lectura.textoCompleto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texto.isEmpty else { return [] }

        let nombre = (lectura.nombre ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let marca = (lectura.marca ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let volumen = lectura.volumenML ?? 750

        let candidato = CandidatoVariante(
            varianteId: UUID(),
            productoId: UUID(),
            nombreProducto: nombre.isEmpty ? "Producto nuevo" : nombre,
            marca: marca,
            categoria: "",
            volumenML: volumen,
            tipo: inferirTipo(texto: texto),
            sabor: "",
            graduacion: lectura.graduacion ?? 0,
            confianza: 0.30,
            fotoRuta: nil,
            esNuevo: true,
            detalleCoincidencias: ["Producto nuevo"],
            fuentes: [.textoEtiqueta]
        )
        return [candidato]
    }

    /// Tipo de producto inferido del texto.
    static func inferirTipo(texto: String) -> String {
        let norm = Unidades.normaliza(texto)
        guard !norm.isEmpty else { return "" }
        if norm.contains("espumoso") || norm.contains("espumante") || norm.contains("brut")
            || norm.contains("prosecco") || norm.contains("cava") {
            return "Espumoso"
        }
        if norm.contains("rosado") { return "Rosado" }
        if norm.contains("blanco") { return "Blanco" }
        if norm.contains("tinto") { return "Tinto" }
        return ""
    }

    /// País probable. Usa `Catalogo.paisProbable` (Bodega/Core/Catalogo.swift), que ya va
    /// compilado en el módulo `Bodega`.
    ///
    /// Nota: no se comprueba el archivo en disco con FileManager porque en la app instalada
    /// el código fuente no existe (el catálogo va compilado) y el país saldría siempre vacío.
    static func paisProbable(_ texto: String) -> String? {
        if let resuelta = resolutorPais { return resuelta(texto) }
        return Catalogo.paisProbable(texto: texto)
    }

    /// "13,5°"
    private static func formateaGrado(_ valor: Double) -> String {
        let texto = String(format: "%.1f", valor).replacingOccurrences(of: ".", with: ",")
        return "\(texto)°"
    }

    /// Orden estable de las fuentes que aportaron puntaje.
    private static func ordenadas(_ fuentes: Set<FuenteDeteccion>) -> [FuenteDeteccion] {
        let orden: [FuenteDeteccion] = [.codigoBarras, .textoEtiqueta, .colorBotella, .similitudVisual]
        return orden.filter { fuentes.contains($0) }
    }
}
