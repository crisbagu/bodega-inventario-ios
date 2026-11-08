import Foundation
import SwiftData

/// Una fila de exportación: la primera celda suele ser la cabecera.
struct FilaExport: Identifiable {
    let id = UUID()
    var columnas: [String]

    init(columnas: [String]) {
        self.columnas = columnas
    }
}

/// Genera archivos CSV y Excel (`.xls` en formato HTML) para compartir.
///
/// Sin `import UIKit`: se puede compilar y probar en macOS.
enum Exportador {

    // MARK: - Carpetas

    /// Carpeta donde se guardan las exportaciones.
    static var carpetaExportaciones: URL {
        AlmacenFotos.raizDocumentos.appendingPathComponent("Exportaciones", isDirectory: true)
    }

    // MARK: - CSV

    /// Genera un CSV con separador `;` (Excel en español) y codificación
    /// UTF-8 con BOM, para que Excel respete los acentos.
    static func csv(filas: [FilaExport]) -> URL {
        let url = urlArchivo(ext: "csv")
        var contenido = ""

        if let cabecera = filas.first {
            contenido += escaparCampos(cabecera.columnas) + "\n"
            for fila in filas.dropFirst() {
                contenido += escaparCampos(fila.columnas) + "\n"
            }
        }

        // BOM UTF-8: sin él, Excel en español rompe los acentos.
        var datos = Data([0xEF, 0xBB, 0xBF])
        datos.append(Data(contenido.utf8))
        try? datos.write(to: url, options: .atomic)
        return url
    }

    /// Une los campos con `;` escapando **cada campo por separado**
    /// (si se escapara la línea entera, el separador quedaría entrecomillado).
    private static func escaparCampos(_ campos: [String]) -> String {
        campos.map { escaparCampo($0) }.joined(separator: ";")
    }

    /// Escapa un campo CSV: entrecomilla si contiene `;`, `"` o salto de línea.
    private static func escaparCampo(_ campo: String) -> String {
        let necesitaComillas = campo.contains(";") || campo.contains("\"") || campo.contains("\n") || campo.contains("\r")
        guard necesitaComillas else { return campo }
        let escapado = campo.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escapado)\""
    }

    // MARK: - Excel

    /// Genera un `.xls` (tabla HTML con `charset utf-8`) compatible con Excel.
    static func excel(filas: [FilaExport], titulo: String) -> URL {
        let url = urlArchivo(ext: "xls")

        var html = """
        <html xmlns:x="urn:schemas-microsoft-com:office:excel">
        <head>
        <meta charset="utf-8">
        <title>\(escaparHTML(titulo))</title>
        <style>
        table { border-collapse: collapse; }
        th, td { border: 1px solid #999; padding: 4px 8px; }
        th { background-color: #eee; font-weight: bold; }
        </style>
        </head>
        <body>
        <h2>\(escaparHTML(titulo))</h2>
        <table>

        """

        if let cabecera = filas.first {
            html += "<tr>"
            for celda in cabecera.columnas {
                html += "<th>\(escaparHTML(celda))</th>"
            }
            html += "</tr>\n"
        }

        for fila in filas.dropFirst() {
            html += "<tr>"
            for celda in fila.columnas {
                html += "<td>\(escaparHTML(celda))</td>"
            }
            html += "</tr>\n"
        }

        html += """
        </table>
        <p>\(escaparHTML(titulo)) — \(filas.count - 1) registros</p>
        </body>
        </html>
        """

        try? Data(html.utf8).write(to: url, options: .atomic)
        return url
    }

    /// Escapa los caracteres especiales de HTML.
    private static func escaparHTML(_ texto: String) -> String {
        texto
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    // MARK: - Filas

    /// Filas de la tabla de movimientos.
    static func filasMovimientos(movimientos: [Movimiento],
                                 variantes: [Variante],
                                 productos: [Producto],
                                 unidad: UnidadVisual) -> [FilaExport] {
        let variantesPorId = Dictionary(variantes.map { ($0.id, $0) }, uniquingKeysWith: { _, nuevo in nuevo })
        let productosPorId = Dictionary(productos.map { ($0.id, $0) }, uniquingKeysWith: { _, nuevo in nuevo })

        let cabecera = FilaExport(columnas: ["Fecha", "Hora", "Tipo", "Producto", "Marca", "Variante",
                                             "Cantidad", "Usuario", "Confianza %", "Anulado",
                                             "Motivo", "Nota", "Foto"])

        var filas: [FilaExport] = [cabecera]

        let formateadorFecha = formateador("dd/MM/yyyy")
        let formateadorHora = formateador("HH:mm")

        for movimiento in movimientos {
            let variante = variantesPorId[movimiento.varianteId]
            let producto = variante.flatMap { productosPorId[$0.productoId] }
            let volumen = variante.map { Unidades.formatea($0.volumenML, unidad: unidad) } ?? ""

            filas.append(FilaExport(columnas: [
                formateadorFecha.string(from: movimiento.fecha),
                formateadorHora.string(from: movimiento.fecha),
                movimiento.tipo.titulo,
                producto?.nombre ?? "",
                producto?.marca ?? "",
                volumen,
                String(movimiento.cantidad),
                movimiento.usuario,
                String(Int((movimiento.confianza * 100).rounded())),
                movimiento.anulado ? "Sí" : "No",
                movimiento.motivoAnulacion,
                movimiento.nota,
                movimiento.fotoRuta ?? ""
            ]))
        }

        return filas
    }

    /// Filas de la tabla de variantes (inventario actual).
    ///
    /// - Parameters:
    ///   - variantes: variantes a exportar.
    ///   - productos: productos, para resolver nombre y marca.
    ///   - unidad: unidad visual en la que se muestran los volúmenes.
    ///   - categorias: opcional. Si se pasa, la columna "Categoría" se rellena.
    ///   - movimientos: opcional. Si se pasa, se rellenan "Stock" y "Última entrada".
    static func filasVariantes(variantes: [Variante],
                               productos: [Producto],
                               unidad: UnidadVisual,
                               categorias: [Categoria] = [],
                               movimientos: [Movimiento] = []) -> [FilaExport] {
        let productosPorId = Dictionary(productos.map { ($0.id, $0) }, uniquingKeysWith: { _, nuevo in nuevo })
        let categoriasPorId = Dictionary(categorias.map { ($0.id, $0) }, uniquingKeysWith: { _, nuevo in nuevo })

        // Stock y última entrada se calculan con los movimientos que se pasan.
        var stockPorVariante: [UUID: Int] = [:]
        var ultimaEntradaPorVariante: [UUID: Date] = [:]
        for movimiento in movimientos where !movimiento.anulado {
            let delta = movimiento.tipo == .entrada ? movimiento.cantidad : -movimiento.cantidad
            stockPorVariante[movimiento.varianteId, default: 0] += delta
            if movimiento.tipo == .entrada {
                if let previa = ultimaEntradaPorVariante[movimiento.varianteId] {
                    if movimiento.fecha > previa {
                        ultimaEntradaPorVariante[movimiento.varianteId] = movimiento.fecha
                    }
                } else {
                    ultimaEntradaPorVariante[movimiento.varianteId] = movimiento.fecha
                }
            }
        }

        let cabecera = FilaExport(columnas: ["Producto", "Marca", "Categoría", "Tipo",
                                             "Volumen (ml)", "Volumen (L)", "Grado",
                                             "Stock", "Stock mínimo", "Cód. barras",
                                             "Nº fotos", "Última entrada"])

        var filas: [FilaExport] = [cabecera]

        let formateadorFecha = formateador("dd/MM/yyyy HH:mm")

        for variante in variantes {
            let producto = productosPorId[variante.productoId]
            let categoria = producto?.categoriaId.flatMap { categoriasPorId[$0] }

            let nombreCategoria: String
            if let categoria {
                let emoji = categoria.emoji.trimmingCharacters(in: .whitespacesAndNewlines)
                nombreCategoria = emoji.isEmpty ? categoria.nombre : "\(categoria.nombre) \(emoji)"
            } else {
                nombreCategoria = ""
            }

            let stock = movimientos.isEmpty ? "" : String(stockPorVariante[variante.id] ?? 0)
            let ultimaEntrada = ultimaEntradaPorVariante[variante.id]
                .map { formateadorFecha.string(from: $0) } ?? ""

            filas.append(FilaExport(columnas: [
                producto?.nombre ?? "",
                producto?.marca ?? "",
                nombreCategoria,
                variante.tipo,
                String(variante.volumenML),
                Unidades.formateaLitros(Double(variante.volumenML) / 1000.0),
                formatearGrado(variante.graduacion),
                stock,
                String(variante.stockMinimo),
                variante.codigoBarras ?? "",
                String(variante.rutasFotos.count),
                ultimaEntrada
            ]))
        }

        return filas
    }

    /// Formatea un grado alcohólico con coma decimal ("13,5 %").
    static func formatearGrado(_ graduacion: Double) -> String {
        guard graduacion > 0 else { return "" }
        let f = NumberFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 1
        let texto = f.string(from: NSNumber(value: graduacion)) ?? "\(graduacion)"
        return "\(texto) %"
    }

    // MARK: - Utilidades

    /// Nombre del archivo con la fecha y hora actual.
    private static func urlArchivo(ext: String) -> URL {
        try? FileManager.default.createDirectory(at: carpetaExportaciones, withIntermediateDirectories: true)
        let marca = formateador("yyyy-MM-dd-HHmm").string(from: Date())
        var url = carpetaExportaciones.appendingPathComponent("export-\(marca).\(ext)")
        var contador = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = carpetaExportaciones.appendingPathComponent("export-\(marca)-\(contador).\(ext)")
            contador += 1
        }
        return url
    }

    private static func formateador(_ formato: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = formato
        return f
    }
}
