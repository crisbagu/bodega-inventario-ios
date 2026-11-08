import Foundation
import SwiftData

// MARK: - Datos de ejemplo

/// Datos de ejemplo de la app: categorías iniciales, un usuario administrador
/// y productos reales (con sus variantes y movimientos) para poder probar
/// conteos, reportes y la galería sin cargar nada a mano.
///
/// La app es 100 % offline: todo se genera localmente, sin red.
///
/// Regla de seguridad: los datos de ejemplo se SIEMPRE pueden borrar sin tocar
/// los productos reales del usuario (ver `borrarTodo`).
enum DatosSemilla {

    // MARK: - Constantes

    /// Marca reservada para marcar datos de prueba (en `notas` del producto).
    static let marcaDemo = "DEMO"

    /// Usuario de ejemplo (quien opera la app en la demo).
    static let nombreUsuarioDemo = "Cris"

    /// Marcas usadas en los productos de ejemplo.
    static let marcasEjemplo: [String] = [
        "Santa Ana", "Barolo", "Chandon", "Johnnie Walker",
        "Herradura", "Brugal", "Campari", "Smirnoff"
    ]

    /// Nombres exactos de los productos de ejemplo.
    static let nombresEjemplo: [String] = [
        "Santa Ana Rosado Espumoso",
        "Barolo Bianco",
        "Chandon Brut",
        "Johnnie Walker",
        "Tequila Herradura Añejo",
        "Ron Brugal Añejo",
        "Campari",
        "Vodka Smirnoff"
    ]

    // MARK: - Carga

    /// Carga los datos de ejemplo SOLO si no se cargaron antes.
    /// Es idempotente: se apoya en `Preferencias.datosSemillaCargados`.
    static func cargarSiHaceFalta(context: ModelContext) {
        guard !Preferencias.datosSemillaCargados else { return }

        crearCategoriasIniciales(context: context)
        crearUsuarioPorDefecto(context: context)
        _ = crearEjemplo(context: context)

        try? context.save()
        Preferencias.datosSemillaCargados = true
    }

    /// Crea las categorías predeterminadas (las que trae la app de fábrica).
    /// No duplica: si ya existe una categoría con ese nombre, la respeta.
    private static func crearCategoriasIniciales(context: ModelContext) {
        let existentes = (try? context.fetch(FetchDescriptor<Categoria>())) ?? []
        let nombresExistentes = Set(existentes.map { $0.nombre.lowercased() })
        for (indice, semilla) in Catalogo.categoriasIniciales.enumerated() {
            guard !nombresExistentes.contains(semilla.nombre.lowercased()) else { continue }
            let categoria = Categoria(nombre: semilla.nombre,
                                     emoji: semilla.emoji,
                                     orden: indice,
                                     esPredeterminada: true)
            context.insert(categoria)
        }
    }

    /// Crea el usuario administrador de la demo ("Cris") si no existe.
    private static func crearUsuarioPorDefecto(context: ModelContext) {
        let usuarios = (try? context.fetch(FetchDescriptor<Usuario>())) ?? []
        let yaExiste = usuarios.contains {
            $0.nombre.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                == nombreUsuarioDemo.lowercased()
        }
        guard !yaExiste else { return }
        let usuario = Usuario(nombre: nombreUsuarioDemo, rol: .administrador, activo: true)
        context.insert(usuario)
    }

    // MARK: - Productos de ejemplo

    /// Crea los productos de ejemplo con sus variantes y movimientos.
    /// - Returns: las variantes creadas (o las de ejemplo ya existentes, si los
    ///   productos de ejemplo ya estaban cargados: nunca se duplican).
    @discardableResult
    static func crearEjemplo(context: ModelContext) -> [Variante] {
        let productos = (try? context.fetch(FetchDescriptor<Producto>())) ?? []
        if productos.contains(where: esProductoEjemplo) {
            // Ya hay datos de ejemplo: no se duplican, se devuelven los que hay.
            return variantesDeEjemplo(context: context)
        }

        let categorias = (try? context.fetch(FetchDescriptor<Categoria>())) ?? []
        var creadas: [Variante] = []

        for semilla in productosEjemplo {
            let producto = Producto(nombre: semilla.nombre,
                                    marca: semilla.marca,
                                    paisOrigen: semilla.pais,
                                    esImportado: Catalogo.esImportado(pais: semilla.pais),
                                    categoriaId: idCategoria(nombre: semilla.categoria, en: categorias),
                                    notas: "Dato de ejemplo de la app · \(marcaDemo)")
            context.insert(producto)

            for (indice, varianteSemilla) in semilla.variantes.enumerated() {
                let variante = Variante(productoId: producto.id,
                                        volumenML: varianteSemilla.volumenML,
                                        tipo: varianteSemilla.tipo,
                                        sabor: varianteSemilla.sabor,
                                        graduacion: varianteSemilla.graduacion,
                                        codigoInterno: "\(marcaDemo)-\(semilla.marca)-\(varianteSemilla.volumenML)-\(indice + 1)",
                                        codigoBarras: nil,
                                        stockMinimo: varianteSemilla.stockMinimo,
                                        rutasFotos: [],
                                        colorDominante: nil)
                context.insert(variante)
                creadas.append(variante)

                for movimientoSemilla in varianteSemilla.movimientos {
                    let movimiento = Movimiento(varianteId: variante.id,
                                                tipo: movimientoSemilla.tipo,
                                                cantidad: movimientoSemilla.cantidad,
                                                fecha: fecha(haceDias: movimientoSemilla.diasAtras),
                                                usuario: nombreUsuarioDemo,
                                                fotoRuta: nil,
                                                nota: movimientoSemilla.nota,
                                                confianza: 0,
                                                anulado: false,
                                                motivoAnulacion: "",
                                                codigoBarras: nil,
                                                textoOCR: "")
                    context.insert(movimiento)
                }
            }
        }

        try? context.save()
        Preferencias.datosSemillaCargados = true
        return creadas
    }

    // MARK: - Borrado

    /// Borra SOLO los datos de ejemplo.
    ///
    /// No toca los productos reales del usuario, ni las categorías
    /// predeterminadas, ni los usuarios. Se identifican los productos de ejemplo
    /// por la marca "DEMO" en sus notas o por tener marca y nombre de las listas
    /// de ejemplo.
    static func borrarTodo(context: ModelContext) {
        let productos = (try? context.fetch(FetchDescriptor<Producto>())) ?? []
        let aBorrar = productos.filter(esProductoEjemplo)
        guard !aBorrar.isEmpty else {
            try? context.save()
            return
        }

        let idsProductos = Set(aBorrar.map { $0.id })
        let variantes = (try? context.fetch(FetchDescriptor<Variante>())) ?? []
        let idsVariantes = Set(variantes.filter { idsProductos.contains($0.productoId) }.map { $0.id })

        // Primero los movimientos de esas variantes...
        let movimientos = (try? context.fetch(FetchDescriptor<Movimiento>())) ?? []
        for movimiento in movimientos where idsVariantes.contains(movimiento.varianteId) {
            context.delete(movimiento)
        }
        // ...luego las variantes...
        for variante in variantes where idsProductos.contains(variante.productoId) {
            context.delete(variante)
        }
        // ...y por último los productos.
        for producto in aBorrar {
            context.delete(producto)
        }

        try? context.save()
        // Se puede volver a cargar la demo desde Ajustes.
        Preferencias.datosSemillaCargados = false
    }

    /// True si el producto es un dato de ejemplo.
    static func esProductoEjemplo(_ producto: Producto) -> Bool {
        let marca = producto.marca.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let nombre = producto.nombre.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Marca explícita de ejemplo.
        if marca == marcaDemo.lowercased() { return true }
        if producto.notas.uppercased().contains(marcaDemo.uppercased()) { return true }
        // Marca y nombre dentro de las listas de ejemplo (ambos, para no tocar
        // productos reales que happen a compartir marca con la demo).
        let marcas = marcasEjemplo.map { $0.lowercased() }
        let nombres = nombresEjemplo.map { $0.lowercased() }
        return marcas.contains(marca) && nombres.contains(nombre)
    }

    /// Variantes que pertenecen a los productos de ejemplo.
    private static func variantesDeEjemplo(context: ModelContext) -> [Variante] {
        let productos = (try? context.fetch(FetchDescriptor<Producto>())) ?? []
        let ids = Set(productos.filter(esProductoEjemplo).map { $0.id })
        guard !ids.isEmpty else { return [] }
        let variantes = (try? context.fetch(FetchDescriptor<Variante>())) ?? []
        return variantes.filter { ids.contains($0.productoId) }
    }

    // MARK: - Utilidades

    /// Busca el id de una categoría por nombre; si no existe usa "Otros".
    private static func idCategoria(nombre: String, en categorias: [Categoria]) -> UUID? {
        if let exacta = categorias.first(where: { $0.nombre.lowercased() == nombre.lowercased() }) {
            return exacta.id
        }
        return categorias.first(where: { $0.nombre.lowercased() == "otros" })?.id
    }

    /// Fecha en el pasado, para que los reportes tengan datos de días anteriores.
    private static func fecha(haceDias dias: Int) -> Date {
        let base = Date()
        guard let fecha = Calendar.current.date(byAdding: .day, value: -dias, to: base) else { return base }
        // Un poco de variación horaria: los movimientos no caen todos al mismo instante.
        let minutos = (dias * 37) % 240
        return Calendar.current.date(byAdding: .minute, value: -minutos, to: fecha) ?? fecha
    }

    // MARK: - Definición de las semillas

    /// Movimiento de ejemplo (entrada o salida) para que los reportes tengan datos.
    private struct MovimientoSemilla {
        let tipo: TipoMovimiento
        let cantidad: Int
        let diasAtras: Int
        let nota: String
    }

    /// Variante de ejemplo: tamaño, tipo, sabor, graduación, mínimo y movimientos.
    private struct VarianteSemilla {
        let volumenML: Int
        let tipo: String
        let sabor: String
        let graduacion: Double
        let stockMinimo: Int
        let movimientos: [MovimientoSemilla]
    }

    /// Producto de ejemplo con sus variantes.
    private struct ProductoSemilla {
        let nombre: String
        let marca: String
        let pais: String
        let categoria: String
        let variantes: [VarianteSemilla]
    }

    /// Los 8 productos de ejemplo con marca y país coherentes:
    /// - Santa Ana (México) es la marca de vino más famosa de México.
    /// - Barolo (Italia) es el nombre del vino italiano por excelencia.
    /// - Chandon (Argentina) es de Mendoza, así que es el único producto local.
    /// - Johnnie Walker (Reino Unido), Herradura (México), Brugal (República Dominicana),
    ///   Campari (Italia) y Smirnoff (Estados Unidos) completan la demo.
    private static let productosEjemplo: [ProductoSemilla] = [
        ProductoSemilla(nombre: "Santa Ana Rosado Espumoso",
                        marca: "Santa Ana",
                        pais: "México",
                        categoria: "Vino rosado espumoso",
                        variantes: [
                            VarianteSemilla(volumenML: 375,
                                            tipo: "Rosado espumoso",
                                            sabor: "Brut",
                                            graduacion: 11.5,
                                            stockMinimo: 2,
                                            movimientos: [
                                                MovimientoSemilla(tipo: .entrada, cantidad: 12, diasAtras: 20, nota: "Compra al proveedor"),
                                                MovimientoSemilla(tipo: .salida, cantidad: 5, diasAtras: 3, nota: "Venta mostrador")
                                            ]),
                            VarianteSemilla(volumenML: 750,
                                            tipo: "Rosado espumoso",
                                            sabor: "Brut",
                                            graduacion: 11.5,
                                            stockMinimo: 3,
                                            movimientos: [
                                                MovimientoSemilla(tipo: .entrada, cantidad: 6, diasAtras: 20, nota: "Compra al proveedor"),
                                                MovimientoSemilla(tipo: .salida, cantidad: 2, diasAtras: 2, nota: "Venta mostrador")
                                            ])
                        ]),
        ProductoSemilla(nombre: "Barolo Bianco",
                        marca: "Barolo",
                        pais: "Italia",
                        categoria: "Vino blanco",
                        variantes: [
                            VarianteSemilla(volumenML: 750,
                                            tipo: "Blanco",
                                            sabor: "Blanco",
                                            graduacion: 13,
                                            stockMinimo: 2,
                                            movimientos: [
                                                MovimientoSemilla(tipo: .entrada, cantidad: 8, diasAtras: 18, nota: "Compra al proveedor"),
                                                MovimientoSemilla(tipo: .salida, cantidad: 3, diasAtras: 4, nota: "Venta mostrador")
                                            ])
                        ]),
        ProductoSemilla(nombre: "Chandon Brut",
                        marca: "Chandon",
                        pais: "Argentina",
                        categoria: "Vino espumoso",
                        variantes: [
                            VarianteSemilla(volumenML: 750,
                                            tipo: "Espumoso",
                                            sabor: "Brut",
                                            graduacion: 12,
                                            stockMinimo: 3,
                                            movimientos: [
                                                MovimientoSemilla(tipo: .entrada, cantidad: 10, diasAtras: 15, nota: "Compra al proveedor"),
                                                MovimientoSemilla(tipo: .salida, cantidad: 4, diasAtras: 5, nota: "Venta mostrador"),
                                                MovimientoSemilla(tipo: .salida, cantidad: 2, diasAtras: 1, nota: "Venta mostrador")
                                            ])
                        ]),
        ProductoSemilla(nombre: "Johnnie Walker",
                        marca: "Johnnie Walker",
                        pais: "Reino Unido",
                        categoria: "Whisky",
                        variantes: [
                            VarianteSemilla(volumenML: 700,
                                            tipo: "Whisky",
                                            sabor: "Red Label",
                                            graduacion: 40,
                                            stockMinimo: 2,
                                            movimientos: [
                                                MovimientoSemilla(tipo: .entrada, cantidad: 6, diasAtras: 25, nota: "Compra al proveedor"),
                                                MovimientoSemilla(tipo: .salida, cantidad: 2, diasAtras: 6, nota: "Venta mostrador")
                                            ]),
                            VarianteSemilla(volumenML: 750,
                                            tipo: "Whisky",
                                            sabor: "Black Label",
                                            graduacion: 40,
                                            stockMinimo: 2,
                                            movimientos: [
                                                MovimientoSemilla(tipo: .entrada, cantidad: 4, diasAtras: 25, nota: "Compra al proveedor"),
                                                MovimientoSemilla(tipo: .salida, cantidad: 1, diasAtras: 2, nota: "Venta mostrador")
                                            ])
                        ]),
        ProductoSemilla(nombre: "Tequila Herradura Añejo",
                        marca: "Herradura",
                        pais: "México",
                        categoria: "Tequila",
                        variantes: [
                            VarianteSemilla(volumenML: 750,
                                            tipo: "Tequila",
                                            sabor: "Añejo",
                                            graduacion: 40,
                                            stockMinimo: 2,
                                            movimientos: [
                                                MovimientoSemilla(tipo: .entrada, cantidad: 6, diasAtras: 22, nota: "Compra al proveedor"),
                                                MovimientoSemilla(tipo: .salida, cantidad: 2, diasAtras: 5, nota: "Venta mostrador")
                                            ])
                        ]),
        ProductoSemilla(nombre: "Ron Brugal Añejo",
                        marca: "Brugal",
                        pais: "República Dominicana",
                        categoria: "Ron",
                        variantes: [
                            VarianteSemilla(volumenML: 700,
                                            tipo: "Ron",
                                            sabor: "Añejo",
                                            graduacion: 40,
                                            stockMinimo: 2,
                                            movimientos: [
                                                MovimientoSemilla(tipo: .entrada, cantidad: 8, diasAtras: 28, nota: "Compra al proveedor"),
                                                MovimientoSemilla(tipo: .salida, cantidad: 3, diasAtras: 7, nota: "Venta mostrador")
                                            ])
                        ]),
        ProductoSemilla(nombre: "Campari",
                        marca: "Campari",
                        pais: "Italia",
                        categoria: "Aperitivo",
                        variantes: [
                            VarianteSemilla(volumenML: 750,
                                            tipo: "Aperitivo",
                                            sabor: "Rojo",
                                            graduacion: 25,
                                            stockMinimo: 2,
                                            movimientos: [
                                                MovimientoSemilla(tipo: .entrada, cantidad: 12, diasAtras: 30, nota: "Compra al proveedor"),
                                                MovimientoSemilla(tipo: .salida, cantidad: 6, diasAtras: 9, nota: "Venta mostrador")
                                            ]),
                            VarianteSemilla(volumenML: 750,
                                            tipo: "Aperitivo",
                                            sabor: "Blanco",
                                            graduacion: 25,
                                            stockMinimo: 1,
                                            movimientos: [
                                                MovimientoSemilla(tipo: .entrada, cantidad: 6, diasAtras: 30, nota: "Compra al proveedor")
                                            ]),
                            VarianteSemilla(volumenML: 1000,
                                            tipo: "Aperitivo",
                                            sabor: "Rojo",
                                            graduacion: 25,
                                            stockMinimo: 1,
                                            movimientos: [
                                                MovimientoSemilla(tipo: .entrada, cantidad: 4, diasAtras: 12, nota: "Compra al proveedor"),
                                                MovimientoSemilla(tipo: .salida, cantidad: 1, diasAtras: 1, nota: "Venta mostrador")
                                            ])
                        ]),
        ProductoSemilla(nombre: "Vodka Smirnoff",
                        marca: "Smirnoff",
                        pais: "Estados Unidos",
                        categoria: "Vodka",
                        variantes: [
                            VarianteSemilla(volumenML: 700,
                                            tipo: "Vodka",
                                            sabor: "",
                                            graduacion: 37.5,
                                            stockMinimo: 2,
                                            movimientos: [
                                                MovimientoSemilla(tipo: .entrada, cantidad: 10, diasAtras: 30, nota: "Compra al proveedor"),
                                                MovimientoSemilla(tipo: .salida, cantidad: 4, diasAtras: 8, nota: "Venta mostrador")
                                            ])
                        ])
    ]
}
