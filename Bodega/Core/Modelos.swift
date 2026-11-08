import Foundation
import SwiftData

// MARK: - Categoría (secciones de la bodega)

@Model
final class Categoria {
    var id: UUID
    var nombre: String
    var emoji: String
    var orden: Int
    var esPredeterminada: Bool

    init(id: UUID = UUID(),
         nombre: String,
         emoji: String = "📦",
         orden: Int = 0,
         esPredeterminada: Bool = false) {
        self.id = id
        self.nombre = nombre
        self.emoji = emoji
        self.orden = orden
        self.esPredeterminada = esPredeterminada
    }
}

// MARK: - Producto base (marca + nombre)

@Model
final class Producto {
    var id: UUID
    var nombre: String
    var marca: String
    var paisOrigen: String
    var esImportado: Bool
    var categoriaId: UUID?
    var notas: String
    var creadoEn: Date

    init(id: UUID = UUID(),
         nombre: String,
         marca: String,
         paisOrigen: String = "",
         esImportado: Bool = false,
         categoriaId: UUID? = nil,
         notas: String = "",
         creadoEn: Date = Date()) {
        self.id = id
        self.nombre = nombre
        self.marca = marca
        self.paisOrigen = paisOrigen
        self.esImportado = esImportado
        self.categoriaId = categoriaId
        self.notas = notas
        self.creadoEn = creadoEn
    }
}

// MARK: - Variante (tamaño, color/tipo, sabor, graduación)

@Model
final class Variante {
    var id: UUID
    var productoId: UUID
    var volumenML: Int
    var tipo: String
    var sabor: String
    var graduacion: Double
    var codigoInterno: String
    var codigoBarras: String?
    var stockMinimo: Int
    /// Rutas relativas dentro de la carpeta Fotos de la app.
    var rutasFotos: [String]
    var colorDominante: String?
    var aciertos: Int
    var intentos: Int
    var creadoEn: Date

    init(id: UUID = UUID(),
         productoId: UUID,
         volumenML: Int,
         tipo: String = "",
         sabor: String = "",
         graduacion: Double = 0,
         codigoInterno: String = "",
         codigoBarras: String? = nil,
         stockMinimo: Int = 0,
         rutasFotos: [String] = [],
         colorDominante: String? = nil,
         aciertos: Int = 0,
         intentos: Int = 0,
         creadoEn: Date = Date()) {
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
}

// MARK: - Movimiento (cada entrada o salida, con su foto)

@Model
final class Movimiento {
    var id: UUID
    var varianteId: UUID
    var tipoRaw: String
    var cantidad: Int
    var fecha: Date
    var usuario: String
    var fotoRuta: String?
    var nota: String
    /// 0...1 confianza del reconocimiento al momento del movimiento.
    var confianza: Double
    var anulado: Bool
    var motivoAnulacion: String
    var codigoBarras: String?
    var textoOCR: String

    init(id: UUID = UUID(),
         varianteId: UUID,
         tipo: TipoMovimiento,
         cantidad: Int,
         fecha: Date = Date(),
         usuario: String = "",
         fotoRuta: String? = nil,
         nota: String = "",
         confianza: Double = 0,
         anulado: Bool = false,
         motivoAnulacion: String = "",
         codigoBarras: String? = nil,
         textoOCR: String = "") {
        self.id = id
        self.varianteId = varianteId
        self.tipoRaw = tipo.rawValue
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

    var tipo: TipoMovimiento {
        get { TipoMovimiento(rawValue: tipoRaw) ?? .entrada }
        set { tipoRaw = newValue.rawValue }
    }
}

// MARK: - Usuario

@Model
final class Usuario {
    var id: UUID
    var nombre: String
    var rolRaw: String
    var activo: Bool

    init(id: UUID = UUID(),
         nombre: String,
         rol: RolUsuario = .operario,
         activo: Bool = true) {
        self.id = id
        self.nombre = nombre
        self.rolRaw = rol.rawValue
        self.activo = activo
    }

    var rol: RolUsuario {
        get { RolUsuario(rawValue: rolRaw) ?? .operario }
        set { rolRaw = newValue.rawValue }
    }
}

// MARK: - Vínculo código de barras → variante (memoria de la app)

// MARK: - Configuración clave/valor

@Model
final class Configuracion {
    var clave: String
    var valor: String

    init(clave: String, valor: String) {
        self.clave = clave
        self.valor = valor
    }
}
