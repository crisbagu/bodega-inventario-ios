import Foundation

// Runner de pruebas sin XCTest (Command Line Tools no lo trae).
// Cada comprobación imprime PASS/FAIL y el proceso termina con código 1 si algo falla.

var fallos = 0
var pruebas = 0

func comprobar(_ condicion: Bool, _ mensaje: String) {
    pruebas += 1
    if condicion {
        print("  PASS  \(mensaje)")
    } else {
        fallos += 1
        print("  FAIL  \(mensaje)")
    }
}

func igual<T: Equatable>(_ valor: T, _ esperado: T, _ mensaje: String) {
    comprobar(valor == esperado, "\(mensaje) (obtenido: \(valor), esperado: \(esperado))")
}

func casiIgual(_ valor: Double, _ esperado: Double, _ mensaje: String, tolerancia: Double = 0.01) {
    comprobar(abs(valor - esperado) <= tolerancia, "\(mensaje) (obtenido: \(valor), esperado: \(esperado))")
}

print("== Conversión de unidades ==")
igual(Unidades.mililitros(texto: "750 ml"), 750, "750 ml → 750")
igual(Unidades.mililitros(texto: "750ml"), 750, "750ml → 750")
igual(Unidades.mililitros(texto: "375 ml"), 375, "375 ml → 375")
igual(Unidades.mililitros(texto: "0,75 L"), 750, "0,75 L → 750")
igual(Unidades.mililitros(texto: "0.75 L"), 750, "0.75 L → 750")
igual(Unidades.mililitros(texto: "1 L"), 1000, "1 L → 1000")
igual(Unidades.mililitros(texto: "1,5 L"), 1500, "1,5 L → 1500")
igual(Unidades.mililitros(texto: "50 cl"), 500, "50 cl → 500")
igual(Unidades.mililitros(texto: "CONTENIDO NETO 700 ml"), 700, "volumen dentro de un texto")
comprobar(Unidades.mililitros(texto: "sin volumen") == nil, "texto sin volumen → nil")

print("== Graduación (no confunde volumen con grado) ==")
casiIgual(Unidades.graduacion(texto: "13,5% vol") ?? 0, 13.5, "13,5% vol → 13.5")
casiIgual(Unidades.graduacion(texto: "40 % ABV") ?? 0, 40, "40 % ABV → 40")
casiIgual(Unidades.graduacion(texto: "alc. 12,5 %") ?? 0, 12.5, "alc. 12,5 % → 12.5")
casiIgual(Unidades.graduacion(texto: "750 ml 13,5 % vol") ?? 0, 13.5, "750 ml 13,5 % vol → 13.5 (no 75)")
casiIgual(Unidades.graduacion(texto: "Volumen 700 ml\n40% vol") ?? 0, 40, "volumen y grado en líneas separadas")

print("== Formato de volumen ==")
igual(Unidades.formatea(375, unidad: .mililitros), "375 ml", "375 en ml")
igual(Unidades.formatea(375, unidad: .litros), "0,375 L", "375 en litros")
igual(Unidades.formatea(1000, unidad: .litros), "1 L", "1000 en litros")
comprobar(Unidades.formateaLargo(750).contains("0,75 L"), "formato largo muestra ml y litros")

print("== Lectura de etiqueta ==")
let etiqueta = """
CASA BODEGAS
SANTA ANA
Rosado Espumoso
750 ml   11,5% vol
"""
let lectura = LectorOCR.parsear(etiqueta)
igual(lectura.volumenML, 750, "lee el volumen de la etiqueta")
casiIgual(lectura.graduacion ?? 0, 11.5, "lee el grado de la etiqueta")
comprobar(lectura.marca != nil, "detecta la marca (\(lectura.marca ?? "nil"))")
comprobar(!lectura.lineas.isEmpty, "conserva las líneas leídas")

let conCodigo = LectorOCR.parsear("Santa Ana 750 ml cod 7801234567890")
igual(conCodigo.codigoBarras, "7801234567890", "detecta el código de barras de 13 dígitos")

print("== Motor de coincidencia ==")
func variante(id: UUID = UUID(),
              producto: String = "Santa Ana",
              marca: String = "Santa Ana",
              tipo: String = "Rosado espumoso",
              sabor: String = "",
              volumen: Int = 750,
              grado: Double = 11.5,
              codigo: String? = nil,
              aciertos: Int = 0,
              intentos: Int = 0) -> VarianteInfo {
    VarianteInfo(id: id,
                 productoId: UUID(),
                 nombreProducto: producto,
                 marca: marca,
                 categoria: "Vino rosado espumoso",
                 tipo: tipo,
                 sabor: sabor,
                 volumenML: volumen,
                 graduacion: grado,
                 codigoBarras: codigo,
                 rutasFotos: [],
                 pais: "Argentina",
                 aciertos: aciertos,
                 intentos: intentos)
}

let conBarras = variante(codigo: "7801234567890")
let candidatosBarras = MotorCoincidencia.candidatos(
    lectura: LecturaEtiqueta(textoCompleto: "Santa Ana 750 ml", codigoBarras: "7801234567890"),
    colorHex: nil,
    variantes: [conBarras])
comprobar(!candidatosBarras.isEmpty, "el código de barras exacto genera candidato")
comprobar((candidatosBarras.first?.confianza ?? 0) >= 0.97, "el código de barras manda (≥ 0,97)")
comprobar(candidatosBarras.first?.detalleCoincidencias.contains { $0.lowercased().contains("barras") } == true,
          "el detalle explica que fue el código de barras")

let otras = [
    variante(id: UUID(), producto: "Santa Ana", marca: "Santa Ana", tipo: "Rosado espumoso", volumen: 750),
    variante(id: UUID(), producto: "Santa Ana", marca: "Santa Ana", tipo: "Blanco", volumen: 750),
    variante(id: UUID(), producto: "Barolo", marca: "Barolo", tipo: "Blanco", volumen: 750),
]
let candidatosMixtos = MotorCoincidencia.candidatos(
    lectura: LecturaEtiqueta(textoCompleto: "SANTA ANA Rosado 750 ml", volumenML: 750),
    colorHex: nil,
    variantes: otras)
comprobar(candidatosMixtos.count > 1, "ofrece alternativas cuando hay varias parecidas")
let suma = candidatosMixtos.reduce(0.0) { $0 + $1.confianza }
casiIgual(suma, 1.0, "las confianzas suman 100 %", tolerancia: 0.02)
comprobar((candidatosMixtos.first?.confianza ?? 0) > (candidatosMixtos.last?.confianza ?? 1),
          "la mejor coincidencia va la primera")

let descartada = MotorCoincidencia.candidatos(
    lectura: LecturaEtiqueta(textoCompleto: "Santa Ana 750 ml", volumenML: 750),
    colorHex: nil,
    variantes: [variante(volumen: 375)])
comprobar(!descartada.contains { $0.esNuevo == false && $0.volumenML == 375 },
          "nunca propone la variante de 375 ml para una foto de 750 ml")

let sinAprender = MotorCoincidencia.candidatos(
    lectura: LecturaEtiqueta(textoCompleto: "SANTA ANA Rosado espumoso 750 ml", volumenML: 750),
    colorHex: nil,
    variantes: [variante(id: UUID()), variante(id: UUID(), producto: "Barolo", marca: "Barolo")])
let aprendido = MotorCoincidencia.candidatos(
    lectura: LecturaEtiqueta(textoCompleto: "SANTA ANA Rosado espumoso 750 ml", volumenML: 750),
    colorHex: nil,
    variantes: [variante(id: UUID(), aciertos: 9, intentos: 10),
                 variante(id: UUID(), producto: "Barolo", marca: "Barolo")])
comprobar((aprendido.first?.confianza ?? 0) > (sinAprender.first?.confianza ?? 1),
          "el aprendizaje sube la confianza de la variante que suele acertar")

let sugerida = MotorCoincidencia.sugerenciasNuevas(
    lectura: LecturaEtiqueta(textoCompleto: "BODEGAS NUEVAS ZINTZUN 750 ml Rosado", volumenML: 750),
    variantes: [])
comprobar(!sugerida.isEmpty, "propone crear el producto si no existe")

print("== Color ==")
comprobar(AnalizadorColor.similitud("#8E3A2C", "#8E3A2C") > 0.9, "el mismo color da similitud alta")
comprobar(AnalizadorColor.similitud("#8E3A2C", "#1E3A8E") < 0.5, "colores distintos dan similitud baja")
igual(AnalizadorColor.similitud(nil, "#8E3A2C"), 0, "sin color no hay similitud")

print("== Catálogo ==")
igual(Catalogo.paisProbable(texto: "Vino chileno"), "Chile", "detecta Chile")
igual(Catalogo.paisProbable(texto: "Vino español de Ribera"), "España", "detecta España")
igual(Catalogo.paisProbable(texto: "Vino argentino Malbec"), "Argentina", "detecta Argentina")
comprobar(Catalogo.categoriasIniciales.count >= 10, "trae las categorías de la bodega (\(Catalogo.categoriasIniciales.count))")

print("")
print(pruebas == fallos ? "TODO CORRECTO" : "FALLOS: \(fallos)")
exit(fallos == 0 ? 0 : 1)
