# Contrato técnico — App "Bodega" (iOS, offline, SwiftUI + SwiftData)

Todo el equipo trabaja contra este contrato. **No cambies las firmas públicas**: si necesitas algo nuevo,
agrégalo como función nueva, no rompas la existente.

## Reglas de oro del proyecto
- iOS 17+, SwiftUI, SwiftData. `SWIFT_VERSION = 5.0` (modo Swift 5, sin concurrencia estricta).
- **Cero APIs externas, cero red, cero nube, cero cuentas.** Solo frameworks de Apple.
- Todo en español (UI y comentarios).
- Las fotos se guardan como archivos; la base solo guarda la ruta relativa.
- Nada de `import UIKit` en `Core/` ni en `Vision/` (para que la lógica se pueda compilar y probar en macOS).
  `UIKit`/`SwiftUI` solo en `UI/` y `Services/`.
- Nada de librerías de pago ni dependencias externas.

## Estructura de carpetas (ya existe parte; respeta los nombres)

```
BodegaApp/
  Bodega/
    App/        BodegaApp.swift, RootView.swift                [Cerebro — no tocar]
    Core/       TiposCompartidos.swift, Unidades.swift,        [Cerebro — no tocar]
                Modelos.swift, Preferencias.swift
                Catalogo.swift, DatosSemilla.swift              [Trabajador A]
    Vision/     OCR.swift, Barras.swift, Color.swift,          [Trabajador B]
                MotorCoincidencia.swift
    Services/   AlmacenFotos.swift, Inventario.swift,           [Trabajador D]
                Respaldo.swift, Exportador.swift,
                Retroalimentacion.swift
    UI/         DesignSystem.swift, Componentes.swift,         [Trabajador C]
                InicioView.swift, CapturaFotoView.swift,
                ConfirmacionView.swift, ListaProductosView.swift,
                DetalleProductoView.swift, GaleriaFotosView.swift,
                MovimientosView.swift, ReportesView.swift,
                AjustesView.swift, CategoriasView.swift,
                UsuariosView.swift
  BodegaTests/  (target de pruebas unitarias)                   [Trabajador B]
  Verificacion/ (arnés SwiftPM que corre en macOS)              [Cerebro]
```

## API ya definida (úsala, no la reescribas)

### Core/TiposCompartidos.swift
- `enum TipoMovimiento { case entrada, salida }` → `.emoji`, `.titulo`
- `enum RolUsuario { case operario, administrador }` → `.titulo`, `.emoji`
- `enum UnidadVisual { case mililitros, litros }` → `.titulo`, `.emoji`
- `enum FuenteDeteccion { case codigoBarras, textoEtiqueta, colorBotella, similitudVisual }` → `.emoji`, `.titulo`, `.pesoBase`
- `struct LecturaEtiqueta { textoCompleto, lineas, marca, nombre, volumenML, graduacion, codigoBarras }`
- `struct VarianteInfo { id, productoId, nombreProducto, marca, categoria, tipo, sabor, volumenML, graduacion, codigoBarras, rutasFotos, pais, aciertos, intentos }` + `.tasaAcierto`
- `struct CandidatoVariante { id, varianteId, productoId, nombreProducto, marca, categoria, volumenML, tipo, sabor, graduacion, confianza, fotoRuta, esNuevo, detalleCoincidencias, fuentes }` + `.porcentaje`
- `struct ResultadoDeteccion { lectura, candidatos, colorDominanteHex, sugerenciasNuevas, analizadoEn }`
- `struct SugerenciaNueva { id, nombreProducto, marca, volumenML, tipo, pais, codigoBarras }`
- `struct PesosCoincidencia { codigoBarras, textoEtiqueta, colorBotella, similitudVisual, umbralAutomatico = 0.90, umbralEleccion = 0.60 }`

### Core/Unidades.swift (`enum Unidades`)
- `static func mililitros(texto: String) -> Int?`
- `static func graduacion(texto: String) -> Double?`
- `static func texto(_ ml: Int) -> String` → "375 ml"
- `static func formatea(_ ml: Int, unidad: UnidadVisual) -> String`
- `static func formateaLargo(_ ml: Int) -> String` → "375 ml · 0,375 L"
- `static func formateaLitros(_ litros: Double) -> String` → "0,375 L" (coma decimal)
- `static func desdeLitros(_ litros: Double) -> Int`
- `static func normaliza(_ texto: String) -> String`
- `static func similitudTexto(_ a: String, _ b: String) -> Double` (0...1)

### Core/Modelos.swift (SwiftData)
`Categoria`, `Producto`, `Variante`, `Movimiento`, `Usuario`, `Configuracion`.
Relaciones por UUID (no uses `@Relationship`): `Variante.productoId`, `Variante.rutasFotos: [String]`,
`Movimiento.varianteId`, `Movimiento.tipo` (computed sobre `tipoRaw`).

### Core/Preferencias.swift (`enum Preferencias`)
`unidadVisual`, `usuarioActual`, `rolActual`, `ultimaCopia`, `diasEntreCopias`, `datosSemillaCargados`,
`vibracionActiva`, `sonidoActivo`, `ladoMaximoFoto`, `borrarTodo()`.

## Contratos de los archivos que faltan

### Trabajador A — `Bodega/Core/Catalogo.swift`
```swift
enum Catalogo {
    static let paises: [String]                 // "Argentina", "España", "Chile", "México", ...
    static let tiposVino: [String]               // "Rosado", "Espumoso", "Blanco", "Tinto", "Rosado espumoso"...
    static let tiposLicor: [String]              // "Whisky", "Tequila", "Ron", "Aperitivo", "Vodka", "Gin", ...
    static let categoriasIniciales: [CategoriaSemilla]   // struct CategoriaSemilla { nombre, emoji }
    static let marcasConocidas: [String]
    static func emojiParaTipo(_ tipo: String) -> String
    static func paisProbable(texto: String) -> String?     // "Chileno" -> "Chile"
    static func esImportado(pais: String) -> Bool
}
```
Categorías iniciales (con emoji): Vino rosado espumoso 🥂, Vino espumoso 🫧, Vino blanco 🍸, Vino tinto 🍷,
Vino argentino 🇦🇷, Vino español 🇪🇸, Vino chileno 🇨🇱, Whisky 🥃, Tequila 🌮, Ron 🍹, Vodka 🧊, Gin 🫗,
Aperitivo 🍋, Cócteles 🍹, Aguardiente 🥃, Sake 🍶, Vinos y espumantes 🍾, Otros 📦.

### Trabajador A — `Bodega/Core/DatosSemilla.swift`
```swift
enum DatosSemilla {
    static func cargarSiHaceFalta(context: ModelContext)   // idempotente, usa Preferencias.datosSemillaCargados
    static func borrarTodo(context: ModelContext)           // borra SOLO los datos de ejemplo (marca "DEMO")
    static func crearEjemplo(context: ModelContext) -> [Variante]
}
```
Datos de ejemplo: 6-8 productos reales (vino rosado espumoso 750 ml, vino blanco 750 ml, whisky 750 ml,
tequila añejo 750 ml, ron añejo 700 ml, aperitivo rojo 750 ml, vodka 700 ml, vino espumoso brut 750 ml),
cada uno con 1-2 variantes (375 ml, 700 ml, 750 ml, 1 L) y marca de ejemplo. Deben servir para probar
conteos, reportes y galería.

### Trabajador B — `Bodega/Vision/OCR.swift`
```swift
enum LectorOCR {
    static func leer(_ imagen: CGImage) async -> LecturaEtiqueta       // Vision, es-ES + en-US
    static func parsear(_ texto: String) -> LecturaEtiqueta            // texto plano -> datos (puro, testeable)
}
```
`parsear` debe extraer: marca, nombre, volumen en ml (usa `Unidades.mililitros`), graduación (usa
`Unidades.graduacion`), código de barras si aparece, y las líneas originales. Usa expresiones regulares
robustas con acentos y mayúsculas/minúsculas.

### Trabajador B — `Bodega/Vision/Barras.swift`
```swift
enum LectorBarras {
    static func codigo(_ imagen: CGImage) async -> String?   // Vision VNDetectBarcodesRequest (EAN-13, EAN-8, UPC, Code-128)
}
```

### Trabajador B — `Bodega/Vision/Color.swift`
```swift
enum AnalizadorColor {
    static func dominante(_ imagen: CGImage) -> String?   // "#RRGGBB" (Core Image)
    static func similitud(_ hexA: String?, _ hexB: String?) -> Double  // 0...1
}
```

### Trabajador B — `Bodega/Vision/MotorCoincidencia.swift`
```swift
enum MotorCoincidencia {
    static func candidatos(lectura: LecturaEtiqueta,
                           colorHex: String?,
                           variantes: [VarianteInfo],
                           pesos: PesosCoincidencia = PesosCoincidencia()) -> [CandidatoVariante]
    static func sugerenciasNuevas(lectura: LecturaEtiqueta, variantes: [VarianteInfo]) -> [SugerenciaNueva]
}
```
Reglas de puntaje (suman puntajes y al final se normalizan a 100 %):
- Código de barras exacto → puntaje = `pesos.codigoBarras` (0,95). Resultado final ≥ 97 % para ese candidato.
- Marca detectada que coincide con la del producto → + 0,35 × pesos.textoEtiqueta.
- Nombre/token del producto aparece en el texto → + 0,45 × pesos.textoEtiqueta (usa `Unidades.similitudTexto`).
- Volumen leído coincide exactamente → + 0,30 × pesos.textoEtiqueta; si el volumen leído NO coincide con el de
  la variante (y ambos se conocen) → esa variante queda descartada (no aparece como candidata).
- Graduación相近 (diferencia ≤ 1,5°) → + 0,10; si difiere más de 3° → descartar.
- Color dominante parecido → + 0,08 (solo si el color no es negro/blanco puro).
- Aprendizaje: multiplica por `1 + 0,15 × tasaAcierto` (máx. ×1,15).
- Devuelve máximo 5 candidatos ordenados de mayor a menor.
- `sugerenciasNuevas`: si el texto trae marca/nombre/volumen y no existe ninguna variante con ese producto,
  devuelve una `SugerenciaNueva` con volumen por defecto 750 ml.

### Trabajador D — `Bodega/Services/AlmacenFotos.swift`
```swift
final class AlmacenFotos {
    static let compartido = AlmacenFotos()
    func guardar(_ imagen: CGImage) throws -> String       // redimensiona a Preferencias.ladoMaximoFoto, JPEG 0,7
    func guardar(_ data: Data) throws -> String
    func url(paraRuta ruta: String) -> URL
    func imagen(paraRuta ruta: String) -> CGImage?
    func datos(paraRuta ruta: String) -> Data?
    func borrar(ruta: String)
    func espacioUsado() -> Int64                            // bytes en disco
    func borrarTodasLasFotos()
}
```
Guarda en `Documents/Fotos/` con nombre `UUID.jpg`. Usa ImageIO/CoreGraphics (no UIKit).

### Trabajador D — `Bodega/Services/Inventario.swift`
```swift
enum Inventario {
    static func stock(varianteId: UUID, context: ModelContext) -> Int
    static func stockMinimoAlerta(context: ModelContext) -> [Variante]
    static func guardarMovimiento(varianteId: UUID, tipo: TipoMovimiento, cantidad: Int, fotoRuta: String?,
                                   nota: String, confianza: Double, usuario: String, textoOCR: String,
                                   codigoBarras: String?, context: ModelContext) throws -> Movimiento
    static func deshacer(movimientoId: UUID, context: ModelContext)
    static func anular(movimientoId: UUID, motivo: String, context: ModelContext)
    static func detectarDuplicado(varianteId: UUID, tipo: TipoMovimiento, cantidad: Int,
                                  context: ModelContext, ventanaSegundos: Int = 8) -> Movimiento?
    static func variantesInfo(context: ModelContext, productos: [Producto], categorias: [Categoria]) -> [VarianteInfo]
}
```
`guardarMovimiento` lanza `Error` con `LocalizedError` si una salida dejaría el stock en negativo
(caso `stockNegativo`). `deshacer` anula el último movimiento (marca `anulado = true`, motivo "Deshecho").
`anular` no borra nada: marca `anulado = true` con motivo, conservando el historial original.

### Trabajador D — `Bodega/Services/Respaldo.swift`
```swift
enum Respaldo {
    static func exportarTodo(context: ModelContext) throws -> URL   // ZIP en Documents/Backups/Bodega-AAAA-MM-DD-HHmm.zip
    static func importar(desde url: URL, context: ModelContext) throws
    static func archivoCopiaReciente() -> URL?
}
```
El ZIP contiene `datos.json` (productos, variantes, movimientos, categorías, usuarios, configuración) y
`fotos/` con las imágenes. Importar reemplaza los datos (con opción de fusionar, no dupliques variantes
con el mismo id).

### Trabajador D — `Bodega/Services/Exportador.swift`
```swift
struct FilaExport: Identifiable { let id = UUID(); var columnas: [String] }
enum Exportador {
    static func csv(filas: [FilaExport]) -> URL
    static func excel(filas: [FilaExport], titulo: String) -> URL   // .xls (tabla HTML compatible con Excel)
    static func filasMovimientos(movimientos: [Movimiento], variantes: [Variante], productos: [Producto],
                                 unidad: UnidadVisual) -> [FilaExport]
    static func filasVariantes(variantes: [Variante], productos: [Producto], unidad: UnidadVisual) -> [FilaExport]
}
```
El archivo se guarda en `Documents/Exportaciones/`. La app lo comparte con `ShareLink`/`UIActivityViewController`.

### Trabajador D — `Bodega/Services/Retroalimentacion.swift`
```swift
enum Retroalimentacion {
    static func exito()
    static func error()
    static func aviso()
}
```
UIFeedbackGenerator + un sonido corto del sistema (SystemSoundID). Respeta `Preferencias.vibracionActiva`
y `Preferencias.sonidoActivo`.

## Trabajador C — Interfaz (SwiftUI)

Sistema de diseño en `UI/DesignSystem.swift`:
- Paleta sobria, fondo oscuro por defecto y soporte de modo claro/oscuro.
- Un color de acento. Tipos: título grande, subtítulo, cuerpo, etiqueta. Espaciado en múltiplos de 4.
- Botones grandes (altura mínima 56 pt), tipografía legible, todo en español.
- Emojis con moderación: uno por sección/estado, nunca una lluvia de emojis.
- `Color.acento` debe existir (lo usa `BodegaApp`). Si lo defines en DesignSystem, no lo declares en Assets.

`UI/Componentes.swift`:
- `TarjetaResumen`, `ChipCategoria`, `ChipConfianza` (muestra el % con color según umbral), `BotonGrande`,
  `FilaVariante`, `VacioEstado` (estado vacío con emoji), `EtiquetaVolumen`, `PastillaEmoji`.

Pantallas (una por archivo, nombres exactos):
1. `InicioView` — dos botones enormes: **Entrada 📥** y **Salida 📤**; resumen de hoy (entradas/salidas),
   alertas de stock bajo, acceso rápido al historial del día y búsqueda.
2. `CapturaFotoView` — wrapper de cámara (UIImagePickerController o equivalente) que devuelve la imagen
   capturada; permisos con `NSCameraUsageDescription` en Info.plist.
3. `ConfirmacionView` — foto capturada, texto reconocido (editable y copiable con botón "Copiar texto"),
   candidatos con % (los 3 primeros con barra de confianza), cantidad con +/- y campo numérico,
   lista para elegir cuando la confianza sea baja, opción "crear variante nueva", nota y botón Guardar.
4. `ListaProductosView` — todos los productos en orden alfabético con stock, buscador, filtros por
   categoría, tamaño, marca y fecha.
5. `DetalleProductoView` — variantes del producto (tamaño, tipo, sabor, graduación, stock, mínimo,
   nº de fotos), galería de fotos de la variante, línea de tiempo de movimientos (quién, cuándo, cuántos),
   deshacer último movimiento y anular movimiento con motivo.
6. `GaleriaFotosView` — fotos agrupadas por producto, orden alfabético, contador de fotos por grupo.
7. `MovimientosView` — movimientos de hoy y de una fecha elegida.
8. `ReportesView` — Swift Charts: productos que más salen, los que menos salen, los que se agotan,
   resumen diario y semanal de entradas/salidas.
9. `AjustesView` — unidad ml/L, usuario actual y rol, gestión de usuarios y categorías, copia de
   seguridad y restauración, exportar CSV/Excel, espacio usado, datos de ejemplo, avisos de copia.
10. `CategoriasView` — crear, renombrar, reordenar y borrar categorías.
11. `UsuariosView` — crear, renombrar, cambiar rol, desactivar y borrar usuarios.

Reglas de UI: todo debe funcionar con una sola mano y con guantes (botones grandes, acciones al alcance
del pulgar, confirmación clara de cada movimiento guardado). Nada de "aspecto empresarial": evita tablas
densas, usa tarjetas y emojis con intención.

## Entrega de cada trabajador
- Escribe solo en los archivos que te tocan.
- Al final, ejecuta `swiftc -parse` sobre cada archivo tuyo y corrige los errores de sintaxis:
  `for f en <tus archivos>; do swiftc -parse "$f" || echo "FALLO $f"; done`
  (no compiles el proyecto completo; no hay Xcode en esta máquina).
- Escribe en tu informe: archivos creados, API públicas que añadiste (por si hay que actualizar el contrato),
  y qué NO pudiste verificar.
