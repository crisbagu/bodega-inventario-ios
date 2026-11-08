import Foundation

// MARK: - Enums de dominio

enum TipoMovimiento: String, Codable, CaseIterable, Identifiable {
    case entrada
    case salida

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .entrada: return "📥"
        case .salida: return "📤"
        }
    }

    var titulo: String {
        switch self {
        case .entrada: return "Entrada"
        case .salida: return "Salida"
        }
    }
}

enum RolUsuario: String, Codable, CaseIterable, Identifiable {
    case operario
    case administrador

    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .operario: return "Operario"
        case .administrador: return "Administrador"
        }
    }

    var emoji: String {
        switch self {
        case .operario: return "🧑‍🔧"
        case .administrador: return "🛡️"
        }
    }
}

enum UnidadVisual: String, Codable, CaseIterable, Identifiable {
    case mililitros
    case litros

    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .mililitros: return "Mililitros"
        case .litros: return "Litros"
        }
    }

    var emoji: String {
        switch self {
        case .mililitros: return "🥛"
        case .litros: return "🛢️"
        }
    }
}

/// De dónde salió el dato que permitió identificar el producto.
enum FuenteDeteccion: String, Codable, CaseIterable {
    case codigoBarras
    case textoEtiqueta
    case colorBotella
    case similitudVisual

    var emoji: String {
        switch self {
        case .codigoBarras: return "🔑"
        case .textoEtiqueta: return "🔤"
        case .colorBotella: return "🎨"
        case .similitudVisual: return "🖼️"
        }
    }

    var titulo: String {
        switch self {
        case .codigoBarras: return "Código de barras"
        case .textoEtiqueta: return "Texto de etiqueta"
        case .colorBotella: return "Color de botella"
        case .similitudVisual: return "Similitud visual"
        }
    }

    /// Peso base de cada fuente cuando se combinan en el puntaje final.
    var pesoBase: Double {
        switch self {
        case .codigoBarras: return 0.95
        case .textoEtiqueta: return 0.55
        case .colorBotella: return 0.08
        case .similitudVisual: return 0.30
        }
    }
}

// MARK: - Lectura de etiqueta

/// Texto y datos leídos de la etiqueta (o escritos a mano por el usuario).
struct LecturaEtiqueta: Codable, Hashable {
    var textoCompleto: String = ""
    var lineas: [String] = []
    var marca: String?
    var nombre: String?
    var volumenML: Int?
    var graduacion: Double?
    var codigoBarras: String?

    var estaVacia: Bool {
        textoCompleto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && codigoBarras == nil
    }

    init(textoCompleto: String = "",
         lineas: [String] = [],
         marca: String? = nil,
         nombre: String? = nil,
         volumenML: Int? = nil,
         graduacion: Double? = nil,
         codigoBarras: String? = nil) {
        self.textoCompleto = textoCompleto
        self.lineas = lineas
        self.marca = marca
        self.nombre = nombre
        self.volumenML = volumenML
        self.graduacion = graduacion
        self.codigoBarras = codigoBarras
    }
}

// MARK: - Variante en memoria (para el motor de coincidencia)

/// Copia plana de una variante. El motor de coincidencia trabaja con esto,
/// no con SwiftData, para poder probarse sin la base de datos.
struct VarianteInfo: Identifiable, Hashable {
    var id: UUID
    var productoId: UUID
    var nombreProducto: String
    var marca: String
    var categoria: String
    var tipo: String
    var sabor: String
    var volumenML: Int
    var graduacion: Double
    var codigoBarras: String?
    var rutasFotos: [String]
    var pais: String
    /// Color dominante de la botella en "#RRGGBB" (lo calcula la app al guardar la foto).
    var colorDominante: String?
    /// Aciertos y intentos del aprendizaje con el uso (0 si es nueva).
    var aciertos: Int
    var intentos: Int

    init(id: UUID,
         productoId: UUID,
         nombreProducto: String,
         marca: String,
         categoria: String,
         tipo: String,
         sabor: String,
         volumenML: Int,
         graduacion: Double,
         codigoBarras: String? = nil,
         rutasFotos: [String] = [],
         pais: String = "",
         colorDominante: String? = nil,
         aciertos: Int = 0,
         intentos: Int = 0) {
        self.id = id
        self.productoId = productoId
        self.nombreProducto = nombreProducto
        self.marca = marca
        self.categoria = categoria
        self.tipo = tipo
        self.sabor = sabor
        self.volumenML = volumenML
        self.graduacion = graduacion
        self.codigoBarras = codigoBarras
        self.rutasFotos = rutasFotos
        self.pais = pais
        self.colorDominante = colorDominante
        self.aciertos = aciertos
        self.intentos = intentos
    }

    /// Porcentaje de aciertos del aprendizaje (0 si nunca se ha usado).
    var tasaAcierto: Double {
        guard intentos > 0 else { return 0 }
        return Double(aciertos) / Double(intentos)
    }
}

// MARK: - Resultados

/// Un candidato propuesto para la foto recién tomada.
struct CandidatoVariante: Identifiable, Hashable {
    var id: UUID = UUID()
    var varianteId: UUID
    var productoId: UUID
    var nombreProducto: String
    var marca: String
    var categoria: String
    var volumenML: Int
    var tipo: String
    var sabor: String
    var graduacion: Double
    /// 0...1
    var confianza: Double
    var fotoRuta: String?
    /// true = es una variante que la app propone crear porque no existe.
    var esNuevo: Bool = false
    /// Por qué coincidió: "Código de barras exacto", "Marca detectada: X"...
    var detalleCoincidencias: [String] = []
    /// Fuentes que aportaron puntaje.
    var fuentes: [FuenteDeteccion] = []

    var porcentaje: Int { Int((confianza * 100).rounded()) }
}

/// Lo que el motor devuelve tras analizar una foto.
struct ResultadoDeteccion {
    var lectura: LecturaEtiqueta
    var candidatos: [CandidatoVariante]
    var colorDominanteHex: String?
    /// Variantes nuevas sugeridas (producto/variante que no está en la base).
    var sugerenciasNuevas: [SugerenciaNueva]
    /// Fecha en que se hizo el análisis.
    var analizadoEn: Date = Date()

    init(lectura: LecturaEtiqueta,
         candidatos: [CandidatoVariante],
         colorDominanteHex: String? = nil,
         sugerenciasNuevas: [SugerenciaNueva] = []) {
        self.lectura = lectura
        self.candidatos = candidatos
        self.colorDominanteHex = colorDominanteHex
        self.sugerenciasNuevas = sugerenciasNuevas
    }
}

/// Propuesta de variante nueva a partir de la lectura de la etiqueta.
struct SugerenciaNueva: Identifiable, Hashable {
    var id: UUID = UUID()
    var nombreProducto: String
    var marca: String
    var volumenML: Int
    var tipo: String
    var pais: String?
    var codigoBarras: String?

    init(nombreProducto: String,
         marca: String,
         volumenML: Int,
         tipo: String,
         pais: String? = nil,
         codigoBarras: String? = nil) {
        self.nombreProducto = nombreProducto
        self.marca = marca
        self.volumenML = volumenML
        self.tipo = tipo
        self.pais = pais
        self.codigoBarras = codigoBarras
    }
}

// MARK: - Pesos del motor

/// Pesos del motor de coincidencia. Ajustables desde Ajustes.
struct PesosCoincidencia: Codable, Equatable {
    var codigoBarras: Double = FuenteDeteccion.codigoBarras.pesoBase
    var textoEtiqueta: Double = FuenteDeteccion.textoEtiqueta.pesoBase
    var colorBotella: Double = FuenteDeteccion.colorBotella.pesoBase
    var similitudVisual: Double = FuenteDeteccion.similitudVisual.pesoBase

    /// Umbral desde el cual basta un toque para confirmar.
    var umbralAutomatico: Double = 0.90
    /// Umbral por debajo del cual hay que elegir a mano.
    var umbralEleccion: Double = 0.60
}
