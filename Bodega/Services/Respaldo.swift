import Foundation
import SwiftData
import Compression

/// Copias de seguridad: exporta e importa todo el contenido de la app.
///
/// El ZIP se escribe y se lee **nativamente** (Compression framework), sin
/// depender de `/usr/bin/zip` ni de `/usr/bin/unzip`:
/// - Esos binarios no existen en el sandbox de iOS (solo están en macOS),
///   así que usar `Process` haría fallar la copia de seguridad en el iPhone.
/// - `COMPRESSION_ZLIB` de Apple produce *deflate crudo* (RFC 1951), que es
///   exactamente el formato que espera el método 8 de ZIP. El archivo generado
///   es un ZIP estándar y se abre con cualquier descompresor.
///
/// Sin `import UIKit`: se puede compilar y probar en macOS.
enum Respaldo {

    // MARK: - Errores

    enum ErrorRespaldo: LocalizedError {
        case archivoIlegible
        case jsonInvalido
        case zipInvalido(String)

        var errorDescription: String? {
            switch self {
            case .archivoIlegible:
                return "No se pudo leer el archivo de copia de seguridad."
            case .jsonInvalido:
                return "La copia de seguridad no tiene datos legibles."
            case .zipInvalido(let motivo):
                return "La copia de seguridad está dañada: \(motivo)"
            }
        }
    }

    /// Resumen de lo que se importó.
    struct ResultadoImportacion {
        var productos: Int = 0
        var variantes: Int = 0
        var movimientos: Int = 0
        var fotos: Int = 0
    }

    // MARK: - Carpetas

    /// Carpeta donde se guardan las copias.
    static var carpetaBackups: URL {
        AlmacenFotos.raizDocumentos.appendingPathComponent("Backups", isDirectory: true)
    }

    // MARK: - Exportar

    /// Crea una copia completa de la base de datos y de las fotos en un ZIP.
    ///
    /// El ZIP queda en `Documents/Backups/Bodega-AAAA-MM-dd-HHmm.zip` y contiene
    /// `datos.json` (categorías, productos, variantes, movimientos, usuarios y
    /// configuración) y la carpeta `fotos/` con todas las imágenes.
    @discardableResult
    static func exportarTodo(context: ModelContext) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: carpetaBackups, withIntermediateDirectories: true)

        let datos = try datosJSON(context: context)

        var entradas: [(nombre: String, datos: Data)] = []
        entradas.append(("datos.json", datos))

        // Fotos: en el ZIP van como "fotos/<nombre>.jpg" y al importar vuelven
        // a `Documents/Fotos/<nombre>.jpg`, que es la ruta que guarda el modelo.
        let almacen = AlmacenFotos.compartido
        almacen.asegurarCarpetas()
        for ruta in almacen.todasLasFotos() {
            guard let bytes = almacen.datos(paraRuta: ruta) else { continue }
            let nombre = "fotos/" + URL(fileURLWithPath: ruta).lastPathComponent
            entradas.append((nombre, bytes))
        }

        let url = destinoCopia()
        try Zip.escribir(entradas: entradas, a: url)

        Preferencias.ultimaCopia = Date()
        return url
    }

    /// Ruta del ZIP con la fecha y hora actual. Si ya existe, añade un sufijo.
    static func destinoCopia() -> URL {
        let marca = formateadorCopia.string(from: Date())
        var url = carpetaBackups.appendingPathComponent("Bodega-\(marca).zip")
        var contador = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = carpetaBackups.appendingPathComponent("Bodega-\(marca)-\(contador).zip")
            contador += 1
        }
        return url
    }

    private static let formateadorCopia: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return f
    }()

    // MARK: - Importar

    /// Restaura una copia de seguridad **fusionando** con lo que ya hay:
    /// nunca duplica entidades con el mismo id.
    ///
    /// - Productos, categorías, variantes, usuarios y configuración se actualizan
    ///   si ya existe su id (o su clave, en el caso de la configuración).
    /// - Los movimientos solo se insertan si su id no existe.
    @discardableResult
    static func importar(desde url: URL, context: ModelContext) throws -> ResultadoImportacion {
        let contenido = try Zip.leer(de: url)

        guard let datosJSON = contenido["datos.json"] else {
            throw ErrorRespaldo.zipInvalido("faltan los datos")
        }

        let decodificador = JSONDecoder()
        decodificador.dateDecodingStrategy = .iso8601
        let paquete: PaqueteRespaldo
        do {
            paquete = try decodificador.decode(PaqueteRespaldo.self, from: datosJSON)
        } catch {
            throw ErrorRespaldo.jsonInvalido
        }

        var resumen = ResultadoImportacion()

        // --- Categorías ---
        for dto in paquete.categorias {
            if let existente = buscarCategoria(id: dto.id, context: context) {
                existente.nombre = dto.nombre
                existente.emoji = dto.emoji
                existente.orden = dto.orden
                existente.esPredeterminada = dto.esPredeterminada
            } else {
                let categoria = Categoria(id: dto.id,
                                          nombre: dto.nombre,
                                          emoji: dto.emoji,
                                          orden: dto.orden,
                                          esPredeterminada: dto.esPredeterminada)
                context.insert(categoria)
            }
        }

        // --- Productos ---
        for dto in paquete.productos {
            if let existente = buscarProducto(id: dto.id, context: context) {
                existente.nombre = dto.nombre
                existente.marca = dto.marca
                existente.paisOrigen = dto.paisOrigen
                existente.esImportado = dto.esImportado
                existente.categoriaId = dto.categoriaId
                existente.notas = dto.notas
                existente.creadoEn = dto.creadoEn
            } else {
                let producto = Producto(id: dto.id,
                                        nombre: dto.nombre,
                                        marca: dto.marca,
                                        paisOrigen: dto.paisOrigen,
                                        esImportado: dto.esImportado,
                                        categoriaId: dto.categoriaId,
                                        notas: dto.notas,
                                        creadoEn: dto.creadoEn)
                context.insert(producto)
            }
            resumen.productos += 1
        }

        // --- Variantes ---
        for dto in paquete.variantes {
            if let existente = buscarVariante(id: dto.id, context: context) {
                existente.productoId = dto.productoId
                existente.volumenML = dto.volumenML
                existente.tipo = dto.tipo
                existente.sabor = dto.sabor
                existente.graduacion = dto.graduacion
                existente.codigoInterno = dto.codigoInterno
                existente.codigoBarras = dto.codigoBarras
                existente.stockMinimo = dto.stockMinimo
                existente.rutasFotos = dto.rutasFotos
                existente.colorDominante = dto.colorDominante
                existente.aciertos = dto.aciertos
                existente.intentos = dto.intentos
                existente.creadoEn = dto.creadoEn
            } else {
                let variante = Variante(id: dto.id,
                                        productoId: dto.productoId,
                                        volumenML: dto.volumenML,
                                        tipo: dto.tipo,
                                        sabor: dto.sabor,
                                        graduacion: dto.graduacion,
                                        codigoInterno: dto.codigoInterno,
                                        codigoBarras: dto.codigoBarras,
                                        stockMinimo: dto.stockMinimo,
                                        rutasFotos: dto.rutasFotos,
                                        colorDominante: dto.colorDominante,
                                        aciertos: dto.aciertos,
                                        intentos: dto.intentos,
                                        creadoEn: dto.creadoEn)
                context.insert(variante)
            }
            resumen.variantes += 1
        }

        // --- Movimientos (solo los que no existen) ---
        let idsExistentes = Set((try? context.fetch(FetchDescriptor<Movimiento>()))?.map { $0.id } ?? [])
        for dto in paquete.movimientos where !idsExistentes.contains(dto.id) {
            let movimiento = Movimiento(id: dto.id,
                                        varianteId: dto.varianteId,
                                        tipo: dto.tipo,
                                        cantidad: dto.cantidad,
                                        fecha: dto.fecha,
                                        usuario: dto.usuario,
                                        fotoRuta: dto.fotoRuta,
                                        nota: dto.nota,
                                        confianza: dto.confianza,
                                        anulado: dto.anulado,
                                        motivoAnulacion: dto.motivoAnulacion,
                                        codigoBarras: dto.codigoBarras,
                                        textoOCR: dto.textoOCR)
            context.insert(movimiento)
            resumen.movimientos += 1
        }

        // --- Usuarios ---
        for dto in paquete.usuarios {
            if let existente = buscarUsuario(id: dto.id, context: context) {
                existente.nombre = dto.nombre
                existente.rolRaw = dto.rolRaw
                existente.activo = dto.activo
            } else {
                let usuario = Usuario(id: dto.id, nombre: dto.nombre, activo: dto.activo)
                usuario.rolRaw = dto.rolRaw
                context.insert(usuario)
            }
        }

        // --- Configuración (se identifica por clave) ---
        for dto in paquete.configuracion {
            if let existente = buscarConfiguracion(clave: dto.clave, context: context) {
                existente.valor = dto.valor
            } else {
                context.insert(Configuracion(clave: dto.clave, valor: dto.valor))
            }
        }

        // --- Fotos ---
        resumen.fotos = restaurarFotos(contenido: contenido)

        try context.save()
        return resumen
    }

    /// Vuelve a escribir las fotos del ZIP en `Documents/Fotos/`.
    /// Devuelve cuántas se recuperaron.
    private static func restaurarFotos(contenido: [String: Data]) -> Int {
        let fm = FileManager.default
        let almacen = AlmacenFotos.compartido
        almacen.asegurarCarpetas()

        var recuperadas = 0
        for (nombre, bytes) in contenido where nombre.hasPrefix("fotos/") {
            let base = URL(fileURLWithPath: nombre).lastPathComponent
            guard !base.isEmpty else { continue }
            let destino = almacen.carpetaFotos.appendingPathComponent(base)
            if fm.fileExists(atPath: destino.path) {
                // Ya existe: no se sobreescribe para no perder fotos nuevas.
                continue
            }
            do {
                try bytes.write(to: destino, options: .atomic)
                recuperadas += 1
            } catch {
                continue
            }
        }
        return recuperadas
    }

    // MARK: - Listado de copias

    /// Todas las copias guardadas, de la más reciente a la más antigua.
    static func listarCopias() -> [URL] {
        let fm = FileManager.default
        guard let contenido = try? fm.contentsOfDirectory(at: carpetaBackups,
                                                         includingPropertiesForKeys: [.contentModificationDateKey],
                                                         options: [.skipsHiddenFiles]) else { return [] }
        return contenido
            .filter { $0.pathExtension.lowercased() == "zip" }
            .sorted { lhs, rhs in
                let fechaL = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let fechaR = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                if fechaL != fechaR { return fechaL > fechaR }
                return lhs.lastPathComponent > rhs.lastPathComponent
            }
    }

    /// La copia más reciente, si hay alguna.
    static func archivoCopiaReciente() -> URL? {
        listarCopias().first
    }

    /// Tamaño en bytes de una copia.
    static func tamanoCopia(at url: URL) -> Int64 {
        let valores = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(valores?.fileSize ?? 0)
    }

    // MARK: - JSON

    /// Construye el `datos.json` de la copia de seguridad.
    static func datosJSON(context: ModelContext) throws -> Data {
        let categorias = (try? context.fetch(FetchDescriptor<Categoria>())) ?? []
        let productos = (try? context.fetch(FetchDescriptor<Producto>())) ?? []
        let variantes = (try? context.fetch(FetchDescriptor<Variante>())) ?? []
        let movimientos = (try? context.fetch(FetchDescriptor<Movimiento>())) ?? []
        let usuarios = (try? context.fetch(FetchDescriptor<Usuario>())) ?? []
        let configuracion = (try? context.fetch(FetchDescriptor<Configuracion>())) ?? []

        let paquete = PaqueteRespaldo(version: 1,
                                      exportadoEn: Date(),
                                      categorias: categorias.map { CategoriaDTO($0) },
                                      productos: productos.map { ProductoDTO($0) },
                                      variantes: variantes.map { VarianteDTO($0) },
                                      movimientos: movimientos.map { MovimientoDTO($0) },
                                      usuarios: usuarios.map { UsuarioDTO($0) },
                                      configuracion: configuracion.map { ConfiguracionDTO($0) })

        let codificador = JSONEncoder()
        codificador.outputFormatting = [.prettyPrinted, .sortedKeys]
        codificador.dateEncodingStrategy = .iso8601
        return try codificador.encode(paquete)
    }

    // MARK: - Búsquedas por id

    private static func buscarCategoria(id: UUID, context: ModelContext) -> Categoria? {
        var descriptor = FetchDescriptor<Categoria>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func buscarProducto(id: UUID, context: ModelContext) -> Producto? {
        var descriptor = FetchDescriptor<Producto>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func buscarVariante(id: UUID, context: ModelContext) -> Variante? {
        var descriptor = FetchDescriptor<Variante>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func buscarUsuario(id: UUID, context: ModelContext) -> Usuario? {
        var descriptor = FetchDescriptor<Usuario>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func buscarConfiguracion(clave: String, context: ModelContext) -> Configuracion? {
        var descriptor = FetchDescriptor<Configuracion>(predicate: #Predicate { $0.clave == clave })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

// MARK: - Estructuras de la copia de seguridad

/// Contenido de `datos.json`.
struct PaqueteRespaldo: Codable {
    var version: Int
    var exportadoEn: Date
    var categorias: [CategoriaDTO]
    var productos: [ProductoDTO]
    var variantes: [VarianteDTO]
    var movimientos: [MovimientoDTO]
    var usuarios: [UsuarioDTO]
    var configuracion: [ConfiguracionDTO]
}

struct CategoriaDTO: Codable {
    var id: UUID
    var nombre: String
    var emoji: String
    var orden: Int
    var esPredeterminada: Bool

    init(id: UUID, nombre: String, emoji: String, orden: Int, esPredeterminada: Bool) {
        self.id = id
        self.nombre = nombre
        self.emoji = emoji
        self.orden = orden
        self.esPredeterminada = esPredeterminada
    }

    init(_ modelo: Categoria) {
        self.init(id: modelo.id,
                  nombre: modelo.nombre,
                  emoji: modelo.emoji,
                  orden: modelo.orden,
                  esPredeterminada: modelo.esPredeterminada)
    }
}

struct ProductoDTO: Codable {
    var id: UUID
    var nombre: String
    var marca: String
    var paisOrigen: String
    var esImportado: Bool
    var categoriaId: UUID?
    var notas: String
    var creadoEn: Date

    init(id: UUID, nombre: String, marca: String, paisOrigen: String, esImportado: Bool, categoriaId: UUID?, notas: String, creadoEn: Date) {
        self.id = id
        self.nombre = nombre
        self.marca = marca
        self.paisOrigen = paisOrigen
        self.esImportado = esImportado
        self.categoriaId = categoriaId
        self.notas = notas
        self.creadoEn = creadoEn
    }

    init(_ modelo: Producto) {
        self.init(id: modelo.id,
                  nombre: modelo.nombre,
                  marca: modelo.marca,
                  paisOrigen: modelo.paisOrigen,
                  esImportado: modelo.esImportado,
                  categoriaId: modelo.categoriaId,
                  notas: modelo.notas,
                  creadoEn: modelo.creadoEn)
    }
}

struct VarianteDTO: Codable {
    var id: UUID
    var productoId: UUID
    var volumenML: Int
    var tipo: String
    var sabor: String
    var graduacion: Double
    var codigoInterno: String
    var codigoBarras: String?
    var stockMinimo: Int
    var rutasFotos: [String]
    var colorDominante: String?
    var aciertos: Int
    var intentos: Int
    var creadoEn: Date

    init(id: UUID, productoId: UUID, volumenML: Int, tipo: String, sabor: String, graduacion: Double, codigoInterno: String, codigoBarras: String?, stockMinimo: Int, rutasFotos: [String], colorDominante: String?, aciertos: Int, intentos: Int, creadoEn: Date) {
        self.id = id
        self.productoId = productoId
        self.volumenML = volumenML
        self.tipo = tipo
        self.sabor = sabor
        self.graduacion = graduacion
        self.codigoInterno = codigoInterno
        self.codigoBarras = codigoBarras
        self.stockMinimo = stockMinimo
        self.rutasFotos = rutasFotos
        self.colorDominante = colorDominante
        self.aciertos = aciertos
        self.intentos = intentos
        self.creadoEn = creadoEn
    }

    init(_ modelo: Variante) {
        self.init(id: modelo.id,
                  productoId: modelo.productoId,
                  volumenML: modelo.volumenML,
                  tipo: modelo.tipo,
                  sabor: modelo.sabor,
                  graduacion: modelo.graduacion,
                  codigoInterno: modelo.codigoInterno,
                  codigoBarras: modelo.codigoBarras,
                  stockMinimo: modelo.stockMinimo,
                  rutasFotos: modelo.rutasFotos,
                  colorDominante: modelo.colorDominante,
                  aciertos: modelo.aciertos,
                  intentos: modelo.intentos,
                  creadoEn: modelo.creadoEn)
    }
}

struct MovimientoDTO: Codable {
    var id: UUID
    var varianteId: UUID
    var tipo: TipoMovimiento
    var cantidad: Int
    var fecha: Date
    var usuario: String
    var fotoRuta: String?
    var nota: String
    var confianza: Double
    var anulado: Bool
    var motivoAnulacion: String
    var codigoBarras: String?
    var textoOCR: String

    init(id: UUID, varianteId: UUID, tipo: TipoMovimiento, cantidad: Int, fecha: Date, usuario: String, fotoRuta: String?, nota: String, confianza: Double, anulado: Bool, motivoAnulacion: String, codigoBarras: String?, textoOCR: String) {
        self.id = id
        self.varianteId = varianteId
        self.tipo = tipo
        self.cantidad = cantidad
        self.fecha = fecha
        self.usuario = usuario
        self.fotoRuta = fotoRuta
        self.nota = nota
        self.confianza = confianza
        self.anulado = anulado
        self.motivoAnulacion = motivoAnulacion
        self.codigoBarras = codigoBarras
        self.textoOCR = textoOCR
    }

    init(_ modelo: Movimiento) {
        self.init(id: modelo.id,
                  varianteId: modelo.varianteId,
                  tipo: modelo.tipo,
                  cantidad: modelo.cantidad,
                  fecha: modelo.fecha,
                  usuario: modelo.usuario,
                  fotoRuta: modelo.fotoRuta,
                  nota: modelo.nota,
                  confianza: modelo.confianza,
                  anulado: modelo.anulado,
                  motivoAnulacion: modelo.motivoAnulacion,
                  codigoBarras: modelo.codigoBarras,
                  textoOCR: modelo.textoOCR)
    }
}

struct UsuarioDTO: Codable {
    var id: UUID
    var nombre: String
    var rolRaw: String
    var activo: Bool

    init(id: UUID, nombre: String, rolRaw: String, activo: Bool) {
        self.id = id
        self.nombre = nombre
        self.rolRaw = rolRaw
        self.activo = activo
    }

    init(_ modelo: Usuario) {
        self.init(id: modelo.id, nombre: modelo.nombre, rolRaw: modelo.rolRaw, activo: modelo.activo)
    }
}

struct ConfiguracionDTO: Codable {
    var clave: String
    var valor: String

    init(clave: String, valor: String) {
        self.clave = clave
        self.valor = valor
    }

    init(_ modelo: Configuracion) {
        self.init(clave: modelo.clave, valor: modelo.valor)
    }
}

// MARK: - ZIP (implementación nativa sobre Compression)

/// Lector y escritor de archivos ZIP (método 8: deflate).
///
/// No usa `/usr/bin/zip` ni `/usr/bin/unzip`: esos binarios no existen en el
/// sandbox de iOS. `COMPRESSION_ZLIB` de Apple produce deflate crudo (RFC 1951),
/// que es lo que exige el método 8 de ZIP, por lo que el archivo resultante es
/// un ZIP estándar compatible con cualquier descompresor.
enum Zip {

    private static let firmaLocal: UInt32 = 0x0403_4b50
    private static let firmaCentral: UInt32 = 0x0201_4b50
    private static let finCentral: UInt32 = 0x0605_4b50

    // MARK: - Escritura

    /// Escribe las entradas dadas en un archivo ZIP.
    static func escribir(entradas: [(nombre: String, datos: Data)], a url: URL) throws {
        var archivo = Data()
        var registros: [RegistroCentral] = []

        for entrada in entradas {
            let crc = CRC32.calcular(entrada.datos)
            let comprimido = comprimir(entrada.datos)
            let usarDeflate = comprimido.count < entrada.datos.count
            let contenido = usarDeflate ? comprimido : entrada.datos
            let metodo: UInt16 = usarDeflate ? 8 : 0
            let tamanoOriginal = entrada.datos.count
            let tamanoComprimido = contenido.count

            let desplazamiento = UInt32(archivo.count)
            let nombreDatos = Data(entrada.nombre.utf8)
            let (hora, fecha) = marcaTiempo(Date())

            // Cabecera local (30 bytes + nombre).
            archivo.appendLE(firmaLocal)
            archivo.appendLE(UInt16(20))          // versión necesaria
            archivo.appendLE(UInt16(0))           // banderas
            archivo.appendLE(metodo)
            archivo.appendLE(hora)
            archivo.appendLE(fecha)
            archivo.appendLE(crc)
            archivo.appendLE(UInt32(tamanoComprimido))
            archivo.appendLE(UInt32(tamanoOriginal))
            archivo.appendLE(UInt16(nombreDatos.count))
            archivo.appendLE(UInt16(0))           // sin campo extra
            archivo.append(nombreDatos)
            archivo.append(contenido)

            registros.append(RegistroCentral(nombre: nombreDatos,
                                              metodo: metodo,
                                              hora: hora,
                                              fecha: fecha,
                                              crc: crc,
                                              tamanoComprimido: tamanoComprimido,
                                              tamanoOriginal: tamanoOriginal,
                                              desplazamiento: desplazamiento))
        }

        // Directorio central.
        let inicioCentral = UInt32(archivo.count)
        for registro in registros {
            archivo.appendLE(firmaCentral)
            archivo.appendLE(UInt16(20))          // versión del creador
            archivo.appendLE(UInt16(20))          // versión necesaria
            archivo.appendLE(UInt16(0))           // banderas
            archivo.appendLE(registro.metodo)
            archivo.appendLE(registro.hora)
            archivo.appendLE(registro.fecha)
            archivo.appendLE(registro.crc)
            archivo.appendLE(UInt32(registro.tamanoComprimido))
            archivo.appendLE(UInt32(registro.tamanoOriginal))
            archivo.appendLE(UInt16(registro.nombre.count))
            archivo.appendLE(UInt16(0))           // extra
            archivo.appendLE(UInt16(0))           // comentario
            archivo.appendLE(UInt16(0))           // número de disco
            archivo.appendLE(UInt16(0))           // atributos internos
            archivo.appendLE(UInt32(0))           // atributos externos
            archivo.appendLE(registro.desplazamiento)
            archivo.append(registro.nombre)
        }
        let tamanoCentral = UInt32(archivo.count) - inicioCentral

        // Fin del directorio central.
        archivo.appendLE(finCentral)
        archivo.appendLE(UInt16(0))
        archivo.appendLE(UInt16(0))
        archivo.appendLE(UInt16(registros.count))
        archivo.appendLE(UInt16(registros.count))
        archivo.appendLE(tamanoCentral)
        archivo.appendLE(inicioCentral)
        archivo.appendLE(UInt16(0))               // sin comentario

        try archivo.write(to: url, options: .atomic)
    }

    private struct RegistroCentral {
        var nombre: Data
        var metodo: UInt16
        var hora: UInt16
        var fecha: UInt16
        var crc: UInt32
        var tamanoComprimido: Int
        var tamanoOriginal: Int
        var desplazamiento: UInt32
    }

    // MARK: - Lectura

    /// Lee todas las entradas de un archivo ZIP.
    static func leer(de url: URL) throws -> [String: Data] {
        guard let archivo = try? Data(contentsOf: url) else {
            throw Respaldo.ErrorRespaldo.archivoIlegible
        }
        let bytes = [UInt8](archivo)

        // Buscar el registro de fin de directorio central (puede tener comentario al final).
        guard let posicionFin = buscarFinCentral(bytes) else {
            throw Respaldo.ErrorRespaldo.zipInvalido("no se encontró el directorio central")
        }

        let entradas = leerUInt16(bytes, posicionFin + 10)
        let tamanoCentral = leerUInt32(bytes, posicionFin + 12)
        let inicioCentral = leerUInt32(bytes, posicionFin + 16)

        var resultado: [String: Data] = [:]
        var cursor = Int(inicioCentral)
        let finCentral = cursor + Int(tamanoCentral)

        for _ in 0..<entradas {
            guard cursor + 46 <= finCentral,
                  leerUInt32(bytes, cursor) == firmaCentral else {
                throw Respaldo.ErrorRespaldo.zipInvalido("directorio central incompleto")
            }
            let metodo = leerUInt16(bytes, cursor + 10)
            let crc = leerUInt32(bytes, cursor + 16)
            let tamanoComprimido = Int(leerUInt32(bytes, cursor + 20))
            let tamanoOriginal = Int(leerUInt32(bytes, cursor + 24))
            let longitudNombre = Int(leerUInt16(bytes, cursor + 28))
            let longitudExtra = Int(leerUInt16(bytes, cursor + 30))
            let longitudComentario = Int(leerUInt16(bytes, cursor + 32))
            let desplazamiento = Int(leerUInt32(bytes, cursor + 42))

            let inicioNombre = cursor + 46
            guard inicioNombre + longitudNombre <= bytes.count else {
                throw Respaldo.ErrorRespaldo.zipInvalido("nombre de archivo truncado")
            }
            let nombre = String(decoding: bytes[inicioNombre..<(inicioNombre + longitudNombre)], as: UTF8.self)

            // Ir a la cabecera local para localizar los datos.
            guard desplazamiento + 30 <= bytes.count,
                  leerUInt32(bytes, desplazamiento) == firmaLocal else {
                throw Respaldo.ErrorRespaldo.zipInvalido("cabecera local inválida")
            }
            let longitudNombreLocal = Int(leerUInt16(bytes, desplazamiento + 26))
            let longitudExtraLocal = Int(leerUInt16(bytes, desplazamiento + 28))
            let inicioDatos = desplazamiento + 30 + longitudNombreLocal + longitudExtraLocal

            guard inicioDatos + tamanoComprimido <= bytes.count else {
                throw Respaldo.ErrorRespaldo.zipInvalido("datos truncados")
            }
            let comprimidos = Data(bytes[inicioDatos..<(inicioDatos + tamanoComprimido)])

            let contenido: Data
            switch metodo {
            case 0:
                contenido = comprimidos
            case 8:
                guard let desinflado = descomprimir(comprimidos, tamanoEsperado: tamanoOriginal) else {
                    throw Respaldo.ErrorRespaldo.zipInvalido("no se pudo descomprimir \(nombre)")
                }
                contenido = desinflado
            default:
                throw Respaldo.ErrorRespaldo.zipInvalido("método de compresión no soportado")
            }

            if CRC32.calcular(contenido) == crc {
                resultado[nombre] = contenido
            }

            cursor = inicioNombre + longitudNombre + longitudExtra + longitudComentario
        }

        return resultado
    }

    private static func buscarFinCentral(_ bytes: [UInt8]) -> Int? {
        guard bytes.count >= 22 else { return nil }
        let limite = max(0, bytes.count - 22 - 65_535)
        var indice = bytes.count - 22
        while indice >= limite {
            if leerUInt32(bytes, indice) == finCentral {
                return indice
            }
            indice -= 1
        }
        return nil
    }

    // MARK: - Deflate

    /// Comprime con deflate crudo (RFC 1951), que es lo que usa el método 8 de ZIP.
    static func comprimir(_ datos: Data) -> Data {
        guard !datos.isEmpty else { return Data() }
        let capacidad = datos.count + (datos.count / 10) + 64
        var salida = Data(count: capacidad)
        let tamanio = salida.withUnsafeMutableBytes { destino -> Int in
            datos.withUnsafeBytes { origen -> Int in
                compression_encode_buffer(destino.bindMemory(to: UInt8.self).baseAddress!,
                                          capacidad,
                                          origen.bindMemory(to: UInt8.self).baseAddress!,
                                          datos.count,
                                          nil,
                                          COMPRESSION_ZLIB)
            }
        }
        guard tamanio > 0 else { return datos }
        return Data(salida.prefix(tamanio))
    }

    /// Descomprime deflate crudo (RFC 1951).
    static func descomprimir(_ datos: Data, tamanoEsperado: Int) -> Data? {
        if datos.isEmpty { return Data() }
        let capacidad = max(tamanoEsperado, 1024)
        var salida = Data(count: capacidad)
        let tamanio = salida.withUnsafeMutableBytes { destino -> Int in
            datos.withUnsafeBytes { origen -> Int in
                compression_decode_buffer(destino.bindMemory(to: UInt8.self).baseAddress!,
                                          capacidad,
                                          origen.bindMemory(to: UInt8.self).baseAddress!,
                                          datos.count,
                                          nil,
                                          COMPRESSION_ZLIB)
            }
        }
        guard tamanio > 0 else { return nil }
        return Data(salida.prefix(tamanio))
    }

    // MARK: - Utilidades de bytes

    private static func leerUInt16(_ bytes: [UInt8], _ indice: Int) -> UInt16 {
        guard indice + 1 < bytes.count else { return 0 }
        return UInt16(bytes[indice]) | (UInt16(bytes[indice + 1]) << 8)
    }

    private static func leerUInt32(_ bytes: [UInt8], _ indice: Int) -> UInt32 {
        guard indice + 3 < bytes.count else { return 0 }
        return UInt32(bytes[indice])
            | (UInt32(bytes[indice + 1]) << 8)
            | (UInt32(bytes[indice + 2]) << 16)
            | (UInt32(bytes[indice + 3]) << 24)
    }

    /// Fecha y hora en el formato de MS-DOS que usa el formato ZIP.
    private static func marcaTiempo(_ fecha: Date) -> (UInt16, UInt16) {
        var calendario = Calendar(identifier: .gregorian)
        calendario.timeZone = TimeZone.current
        let partes = calendario.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fecha)
        let anio = max(1980, partes.year ?? 1980)
        let mes = partes.month ?? 1
        let dia = partes.day ?? 1
        let hora = partes.hour ?? 0
        let minuto = partes.minute ?? 0
        let segundo = partes.second ?? 0
        let horaDOS = UInt16((hora << 11) | (minuto << 5) | (segundo / 2))
        let fechaDOS = UInt16(((anio - 1980) << 9) | (mes << 5) | dia)
        return (horaDOS, fechaDOS)
    }
}

// MARK: - CRC32

/// Cálculo de CRC-32 (polinomio 0xEDB88320), el que usa el formato ZIP.
enum CRC32 {
    private static let tabla: [UInt32] = {
        var tabla = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) == 1 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
            }
            tabla[i] = c
        }
        return tabla
    }()

    static func calcular(_ datos: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in datos {
            crc = tabla[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

// MARK: - Extensión de Data para escribir enteros en little-endian

private extension Data {
    mutating func appendLE(_ valor: UInt16) {
        append(UInt8(valor & 0xFF))
        append(UInt8((valor >> 8) & 0xFF))
    }

    mutating func appendLE(_ valor: UInt32) {
        append(UInt8(valor & 0xFF))
        append(UInt8((valor >> 8) & 0xFF))
        append(UInt8((valor >> 16) & 0xFF))
        append(UInt8((valor >> 24) & 0xFF))
    }
}
