import Foundation
import SwiftData

/// Lógica de inventario: stock, movimientos, anulaciones y aprendizaje.
///
/// Sin `import UIKit`: se puede compilar y probar en macOS.
enum Inventario {

    // MARK: - Errores

    /// Errores de negocio del inventario.
    ///
    /// Nota: el modelo `VinculoBarras` que menciona el contrato todavía no existe
    /// en `Core/Modelos.swift`, así que los vínculos código de barras → variante se
    /// guardan en el modelo `Configuracion` (que sí existe), con la clave
    /// `"barras.<codigo>"` y el valor `"<varianteId>|<aciertos>"`.
    /// Así este archivo no depende de archivos ajenos.
    enum ErrorInventario: LocalizedError {
        /// Una salida dejaría el stock en negativo.
        /// - Parameters:
        ///   - varianteId: variante afectada.
        ///   - disponible: unidades que había antes de la salida.
        ///   - cantidad: unidades que se pidieron.
        case stockNegativo(varianteId: UUID, disponible: Int, cantidad: Int)
        /// La cantidad debe ser mayor que cero.
        case cantidadInvalida
        /// La variante no existe en la base.
        case varianteNoEncontrada(UUID)
        /// El producto no existe en la base.
        case productoNoEncontrado(UUID)

        var errorDescription: String? {
            switch self {
            case .stockNegativo(_, let disponible, let cantidad):
                if cantidad > 0 {
                    return "No hay stock suficiente: hay \(disponible) y pediste \(cantidad)."
                }
                return "No hay stock suficiente: hay \(disponible) disponibles."
            case .cantidadInvalida:
                return "La cantidad debe ser mayor que cero."
            case .varianteNoEncontrada:
                return "No se encontró la variante indicada."
            case .productoNoEncontrado:
                return "No se encontró el producto indicado."
            }
        }

        /// Atajo para lanzar el error de stock desde cualquier sitio.
        static func thrownStockNegativo(varianteId: UUID, disponible: Int, cantidad: Int) -> ErrorInventario {
            .stockNegativo(varianteId: varianteId, disponible: disponible, cantidad: cantidad)
        }
    }

    // MARK: - Stock

    /// Stock actual de una variante: entradas − salidas de los movimientos no anulados.
    static func stock(varianteId: UUID, context: ModelContext) -> Int {
        let movimientos = movimientosDe(varianteId: varianteId, context: context)
        return calcularStock(movimientos)
    }

    /// Variantes cuyo stock está por debajo o en el mínimo configurado.
    static func stockMinimoAlerta(context: ModelContext) -> [Variante] {
        let variantes = todasLasVariantes(context: context)
        guard !variantes.isEmpty else { return [] }

        let todos = todosLosMovimientos(context: context)
        var stockPorVariante: [UUID: Int] = [:]
        for movimiento in todos where !movimiento.anulado {
            let delta = movimiento.tipo == .entrada ? movimiento.cantidad : -movimiento.cantidad
            stockPorVariante[movimiento.varianteId, default: 0] += delta
        }

        return variantes
            .filter { (stockPorVariante[$0.id] ?? 0) <= $0.stockMinimo }
            .sorted { lhs, rhs in
                let stockL = stockPorVariante[lhs.id] ?? 0
                let stockR = stockPorVariante[rhs.id] ?? 0
                if stockL != stockR { return stockL < stockR }
                return lhs.codigoInterno < rhs.codigoInterno
            }
    }

    // MARK: - Movimientos

    /// Registra una entrada o una salida.
    ///
    /// - Throws: `ErrorInventario.cantidadInvalida` si la cantidad no es positiva,
    ///   `ErrorInventario.varianteNoEncontrada` si la variante no existe, o
    ///   `ErrorInventario.stockNegativo` si la salida dejaría el stock en negativo.
    @discardableResult
    static func guardarMovimiento(varianteId: UUID,
                                   tipo: TipoMovimiento,
                                   cantidad: Int,
                                   fotoRuta: String?,
                                   nota: String,
                                   confianza: Double,
                                   usuario: String,
                                   textoOCR: String,
                                   codigoBarras: String?,
                                   context: ModelContext) throws -> Movimiento {
        guard cantidad > 0 else {
            throw ErrorInventario.cantidadInvalida
        }
        guard let variante = variante(id: varianteId, context: context) else {
            throw ErrorInventario.varianteNoEncontrada(varianteId)
        }

        if tipo == .salida {
            let disponible = stock(varianteId: varianteId, context: context)
            if disponible - cantidad < 0 {
                throw ErrorInventario.stockNegativo(varianteId: varianteId,
                                                    disponible: disponible,
                                                    cantidad: cantidad)
            }
        }

        let movimiento = Movimiento(varianteId: varianteId,
                                    tipo: tipo,
                                    cantidad: cantidad,
                                    usuario: usuario.isEmpty ? Preferencias.usuarioActual : usuario,
                                    fotoRuta: fotoRuta,
                                    nota: nota,
                                    confianza: min(max(confianza, 0), 1),
                                    codigoBarras: codigoBarras,
                                    textoOCR: textoOCR)
        context.insert(movimiento)

        // Vínculo código de barras → variante (guardado en Configuracion).
        if let codigo = codigoBarras?.trimmingCharacters(in: .whitespacesAndNewlines), !codigo.isEmpty {
            if variante.codigoBarras == nil || variante.codigoBarras?.isEmpty == true {
                variante.codigoBarras = codigo
            }
            registrarAciertoBarras(codigo: codigo, varianteId: varianteId, context: context)
            registrarAcierto(varianteId: varianteId, context: context)
        }

        try context.save()
        return movimiento
    }

    /// Anula el último movimiento con el motivo "Deshecho". No borra nada.
    static func deshacer(movimientoId: UUID, context: ModelContext) {
        anular(movimientoId: movimientoId, motivo: "Deshecho", context: context)
    }

    /// Anula un movimiento conservando el historial original.
    static func anular(movimientoId: UUID, motivo: String, context: ModelContext) {
        guard let movimiento = movimiento(id: movimientoId, context: context) else { return }
        movimiento.anulado = true
        movimiento.motivoAnulacion = motivo
        try? context.save()
    }

    /// Detecta un movimiento repetido casi idéntico (misma variante, mismo tipo,
    /// misma cantidad) hecho dentro de la ventana de tiempo indicada.
    static func detectarDuplicado(varianteId: UUID,
                                  tipo: TipoMovimiento,
                                  cantidad: Int,
                                  context: ModelContext,
                                  ventanaSegundos: Int = 8) -> Movimiento? {
        let limite = Date().addingTimeInterval(-Double(ventanaSegundos))
        let candidatos = movimientosDe(varianteId: varianteId, context: context)
            .filter { !$0.anulado }
            .filter { $0.tipo == tipo && $0.cantidad == cantidad }
            .filter { $0.fecha >= limite }
        return candidatos.max { $0.fecha < $1.fecha }
    }

    // MARK: - Aprendizaje

    /// Suma un acierto y un intento a la variante (aprendizaje del motor).
    static func registrarAcierto(varianteId: UUID, context: ModelContext) {
        guard let variante = variante(id: varianteId, context: context) else { return }
        variante.aciertos += 1
        variante.intentos += 1
        try? context.save()
    }

    /// Registra un intento fallido (el usuario eligió otra variante).
    static func registrarFallo(varianteId: UUID, context: ModelContext) {
        guard let variante = variante(id: varianteId, context: context) else { return }
        variante.intentos += 1
        try? context.save()
    }

    // MARK: - Vínculos de código de barras (almacenados en Configuracion)

    /// Prefijo de la clave de configuración usada para los vínculos de barras.
    static let prefijoClaveBarras = "barras."

    /// Registra (o actualiza) el vínculo entre un código de barras y una variante,
    /// sumando un acierto. Clave: `"barras.<codigo>"`, valor: `"<varianteId>|<aciertos>"`.
    static func registrarAciertoBarras(codigo: String, varianteId: UUID, context: ModelContext) {
        let clave = prefijoClaveBarras + codigo
        let existente = configuracion(clave: clave, context: context)
        let aciertos = (existente.flatMap { vinculoDesde($0.valor)?.aciertos } ?? 0) + 1
        let valor = "\(varianteId.uuidString)|\(aciertos)"

        if let existente {
            existente.valor = valor
        } else {
            let nueva = Configuracion(clave: clave, valor: valor)
            context.insert(nueva)
        }
        try? context.save()
    }

    /// Variante asociada a un código de barras, si la app ya la conoce.
    static func varianteIdParaBarras(codigo: String, context: ModelContext) -> UUID? {
        guard let configuracion = configuracion(clave: prefijoClaveBarras + codigo, context: context) else {
            return nil
        }
        return vinculoDesde(configuracion.valor)?.varianteId
    }

    /// Aciertos accumulated para un código de barras.
    static func aciertosParaBarras(codigo: String, context: ModelContext) -> Int {
        guard let configuracion = configuracion(clave: prefijoClaveBarras + codigo, context: context) else {
            return 0
        }
        return vinculoDesde(configuracion.valor)?.aciertos ?? 0
    }

    // MARK: - Consulta

    /// Convierte las variantes de SwiftData en `VarianteInfo` (el motor de coincidencia
    /// no conoce SwiftData).
    static func variantesInfo(context: ModelContext,
                              productos: [Producto],
                              categorias: [Categoria]) -> [VarianteInfo] {
        let variantes = todasLasVariantes(context: context)
        let productosPorId = Dictionary(productos.map { ($0.id, $0) }, uniquingKeysWith: { _, nuevo in nuevo })
        let categoriasPorId = Dictionary(categorias.map { ($0.id, $0) }, uniquingKeysWith: { _, nuevo in nuevo })

        return variantes.map { variante in
            let producto = productosPorId[variante.productoId]
            let categoria = producto?.categoriaId.flatMap { categoriasPorId[$0] }

            let nombreCategoria: String
            if let categoria {
                let emoji = categoria.emoji.trimmingCharacters(in: .whitespacesAndNewlines)
                nombreCategoria = emoji.isEmpty ? categoria.nombre : "\(categoria.nombre) \(emoji)"
            } else {
                nombreCategoria = ""
            }

            let aciertos = variante.aciertos
            // `intentos` nunca puede ser menor que 1: así `tasaAcierto` es 0 en vez de NaN.
            let intentos = max(variante.intentos, max(variante.aciertos, 1))

            return VarianteInfo(id: variante.id,
                                 productoId: variante.productoId,
                                 nombreProducto: producto?.nombre ?? "",
                                 marca: producto?.marca ?? "",
                                 categoria: nombreCategoria,
                                 tipo: variante.tipo,
                                 sabor: variante.sabor,
                                 volumenML: variante.volumenML,
                                 graduacion: variante.graduacion,
                                 codigoBarras: variante.codigoBarras,
                                 rutasFotos: variante.rutasFotos,
                                 pais: producto?.paisOrigen ?? "",
                                 aciertos: aciertos,
                                 intentos: intentos)
        }
    }

    /// Crea un producto y su primera variante, con un `codigoInterno` único.
    ///
    /// Formato del código: `SAN-750-R` (prefijo de la marca, volumen en ml y letra del tipo).
    @discardableResult
    static func crearProducto(marca: String,
                               nombre: String,
                               pais: String,
                               esImportado: Bool,
                               categoriaId: UUID?,
                               volumenML: Int,
                               tipo: String,
                               sabor: String,
                               graduacion: Double,
                               codigoBarras: String?,
                               context: ModelContext) throws -> Variante {
        let marcaFinal = marca.trimmingCharacters(in: .whitespacesAndNewlines)
        let nombreFinal = nombre.trimmingCharacters(in: .whitespacesAndNewlines)

        // Si falta el nombre se usa la marca; si faltan ambos, un nombre genérico.
        // (No hace falta fallar: `crearProducto` lanza solo si falla el guardado.)
        let nombreEfectivo: String
        if !nombreFinal.isEmpty {
            nombreEfectivo = nombreFinal
        } else if !marcaFinal.isEmpty {
            nombreEfectivo = marcaFinal
        } else {
            nombreEfectivo = "Producto sin nombre"
        }

        let producto = Producto(nombre: nombreEfectivo,
                                marca: marcaFinal,
                                paisOrigen: pais,
                                esImportado: esImportado,
                                categoriaId: categoriaId)
        context.insert(producto)

        let variante = Variante(productoId: producto.id,
                                volumenML: volumenML,
                                tipo: tipo,
                                sabor: sabor,
                                graduacion: graduacion,
                                codigoInterno: "",
                                codigoBarras: codigoBarras)
        variante.codigoInterno = codigoInternoUnico(marca: marcaFinal,
                                                    volumenML: volumenML,
                                                    tipo: tipo,
                                                    context: context)
        context.insert(variante)

        try context.save()
        return variante
    }

    // MARK: - Utilidades internas

    /// Calcula el stock a partir de una lista de movimientos (entradas − salidas, sin anulados).
    static func calcularStock(_ movimientos: [Movimiento]) -> Int {
        var total = 0
        for movimiento in movimientos where !movimiento.anulado {
            total += movimiento.tipo == .entrada ? movimiento.cantidad : -movimiento.cantidad
        }
        return total
    }

    /// Genera un `codigoInterno` único con el formato `SAN-750-R`.
    static func codigoInternoUnico(marca: String, volumenML: Int, tipo: String, context: ModelContext) -> String {
        let existentes = Set(todasLasVariantes(context: context).map { $0.codigoInterno })

        let prefijo = prefijoCodigo(marca)
        let volumen = max(volumenML, 0)
        let letra = letraTipo(tipo)

        var candidato = "\(prefijo)-\(volumen)-\(letra)"
        if !existentes.contains(candidato) { return candidato }

        var contador = 2
        while existentes.contains(candidato) {
            candidato = "\(prefijo)-\(volumen)-\(letra)\(contador)"
            contador += 1
        }
        return candidato
    }

    /// Tres primeras letras (o menos) de la marca, en mayúsculas y sin acentos.
    static func prefijoCodigo(_ marca: String) -> String {
        let letras = marca.uppercased()
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "es_ES"))
            .unicodeScalars
            .filter { CharacterSet.letters.contains($0) }
            .map(String.init)
            .joined()
        return String(letras.prefix(3)).uppercased().isEmpty ? "GEN" : String(letras.prefix(3)).uppercased()
    }

    /// Primera letra del tipo, en mayúscula (o "X" si no hay tipo).
    static func letraTipo(_ tipo: String) -> String {
        let limpio = tipo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let primera = limpio.first else { return "X" }
        return String(primera).uppercased()
    }

    /// Lee un vínculo `"<varianteId>|<aciertos>"`.
    static func vinculoDesde(_ valor: String) -> (varianteId: UUID, aciertos: Int)? {
        let partes = valor.split(separator: "|", maxSplits: 1).map(String.init)
        guard let id = UUID(uuidString: partes.first ?? ""),
              let aciertos = partes.count > 1 ? Int(partes[1]) : nil else { return nil }
        return (varianteId: id, aciertos: aciertos)
    }

    // MARK: - Acceso a SwiftData

    static func todasLasVariantes(context: ModelContext) -> [Variante] {
        let descriptor = FetchDescriptor<Variante>(sortBy: [SortDescriptor(\.codigoInterno)])
        return (try? context.fetch(descriptor)) ?? []
    }

    static func todosLosMovimientos(context: ModelContext) -> [Movimiento] {
        let descriptor = FetchDescriptor<Movimiento>(sortBy: [SortDescriptor(\.fecha)])
        return (try? context.fetch(descriptor)) ?? []
    }

    static func movimientosDe(varianteId: UUID, context: ModelContext) -> [Movimiento] {
        let id = varianteId
        let descriptor = FetchDescriptor<Movimiento>(
            predicate: #Predicate { $0.varianteId == id },
            sortBy: [SortDescriptor(\.fecha)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    static func variante(id: UUID, context: ModelContext) -> Variante? {
        let objetivo = id
        var descriptor = FetchDescriptor<Variante>(predicate: #Predicate { $0.id == objetivo })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func movimiento(id: UUID, context: ModelContext) -> Movimiento? {
        let objetivo = id
        var descriptor = FetchDescriptor<Movimiento>(predicate: #Predicate { $0.id == objetivo })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func configuracion(clave: String, context: ModelContext) -> Configuracion? {
        let objetivo = clave
        var descriptor = FetchDescriptor<Configuracion>(predicate: #Predicate { $0.clave == objetivo })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
