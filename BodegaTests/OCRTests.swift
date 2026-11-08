import Foundation
import XCTest
@testable import Bodega

/// Pruebas del motor de reconocimiento: parseo de etiqueta, coincidencia de variantes y color.
final class OCRTests: XCTestCase {

    // MARK: - Volumen

    func testParsearVolumen() {
        XCTAssertEqual(LectorOCR.parsear("750 ml").volumenML, 750)
        XCTAssertEqual(LectorOCR.parsear("0,75 L").volumenML, 750)
        XCTAssertEqual(LectorOCR.parsear("1 L").volumenML, 1000)
        XCTAssertEqual(LectorOCR.parsear("375ml").volumenML, 375)
        XCTAssertEqual(LectorOCR.parsear("50 cl").volumenML, 500)
    }

    func testParsearVolumenEnEtiquetaCompleta() {
        let lectura = LectorOCR.parsear("""
        SANTA ANA
        Malbec Reserva
        750 ml
        13,5 % vol
        """)
        XCTAssertEqual(lectura.volumenML, 750)
        XCTAssertEqual(lectura.graduacion ?? 0, 13.5, accuracy: 0.001)
    }

    // MARK: - Graduación

    func testParsearGraduacion() {
        XCTAssertEqual(LectorOCR.parsear("13,5% vol").graduacion ?? 0, 13.5, accuracy: 0.001)
        XCTAssertEqual(LectorOCR.parsear("40 % ABV").graduacion ?? 0, 40, accuracy: 0.001)
    }

    // MARK: - Marca y nombre

    func testParsearMarcaYNombre() {
        let lectura = LectorOCR.parsear("""
        SANTA ANA
        Malbec Reserva
        750 ml
        13,5 % vol
        """)
        XCTAssertNotNil(lectura.marca)
        XCTAssertNotNil(lectura.nombre)
        XCTAssertEqual(lectura.marca, "Santa Ana")
        XCTAssertEqual(lectura.nombre, "Malbec Reserva")
        XCTAssertEqual(lectura.lineas.count, 4)
    }

    // MARK: - Código de barras

    func testCodigoBarrasEnTexto() {
        let lectura = LectorOCR.parsear("Codigo 7801234567890")
        XCTAssertEqual(lectura.codigoBarras, "7801234567890")
    }

    func testSinCodigoBarras() {
        XCTAssertNil(LectorOCR.parsear("SANTA ANA Malbec Reserva 750 ml").codigoBarras)
    }

    // MARK: - Motor de coincidencia

    func testMotorBarrasExacto() {
        let codigo = "7801234567890"
        let lectura = LecturaEtiqueta(textoCompleto: "SANTA ANA Malbec Reserva 750 ml 13,5 % vol \(codigo)",
                                      lineas: ["SANTA ANA", "Malbec Reserva", "750 ml", codigo],
                                      marca: "Santa Ana",
                                      nombre: "Malbec Reserva",
                                      volumenML: 750,
                                      graduacion: 13.5,
                                      codigoBarras: codigo)

        let variante = variantePrueba(nombre: "Vino Malbec Reserva",
                                      marca: "Santa Ana",
                                      volumen: 750,
                                      graduacion: 13.5,
                                      codigo: codigo)

        let candidatos = MotorCoincidencia.candidatos(lectura: lectura, colorHex: nil, variantes: [variante])
        XCTAssertEqual(candidatos.count, 1)
        XCTAssertGreaterThanOrEqual(candidatos.first?.confianza ?? 0, 0.95)
        XCTAssertTrue(candidatos.first?.detalleCoincidencias.contains("Código de barras exacto") ?? false)
        XCTAssertTrue(candidatos.first?.fuentes.contains(.codigoBarras) ?? false)
    }

    func testMotorDescartaVolumenDistinto() {
        let lectura = LecturaEtiqueta(textoCompleto: "SANTA ANA Malbec Reserva 750 ml",
                                      lineas: ["SANTA ANA", "Malbec Reserva", "750 ml"],
                                      marca: "Santa Ana",
                                      nombre: "Malbec Reserva",
                                      volumenML: 750)

        let variante375 = variantePrueba(nombre: "Vino Malbec Reserva", marca: "Santa Ana", volumen: 375)
        let variante750 = variantePrueba(nombre: "Vino Malbec Reserva", marca: "Santa Ana", volumen: 750)

        let candidatos = MotorCoincidencia.candidatos(lectura: lectura,
                                                       colorHex: nil,
                                                       variantes: [variante375, variante750])

        XCTAssertFalse(candidatos.contains { $0.volumenML == 375 })
        XCTAssertTrue(candidatos.contains { $0.volumenML == 750 })
    }

    func testMotorNormaliza() {
        let lectura = LecturaEtiqueta(textoCompleto: "SANTA ANA Malbec Reserva 750 ml 13,5 % vol",
                                      lineas: ["SANTA ANA", "Malbec Reserva", "750 ml"],
                                      marca: "Santa Ana",
                                      nombre: "Malbec Reserva",
                                      volumenML: 750,
                                      graduacion: 13.5)

        let variantes = [
            variantePrueba(nombre: "Vino Malbec Reserva", marca: "Santa Ana", volumen: 750, graduacion: 13.5),
            variantePrueba(nombre: "Vino Malbec", marca: "Santa Ana", volumen: 750, graduacion: 12.5),
            variantePrueba(nombre: "Vino Tinto", marca: "Santa Ana", volumen: 750, graduacion: 13.0)
        ]

        let candidatos = MotorCoincidencia.candidatos(lectura: lectura, colorHex: nil, variantes: variantes)
        XCTAssertFalse(candidatos.isEmpty)

        let suma = candidatos.reduce(0.0) { $0 + $1.confianza }
        XCTAssertEqual(suma, 1.0, accuracy: 0.002)

        // Ordenadas de mayor a menor.
        for indice in 1..<max(candidatos.count, 1) where indice < candidatos.count {
            XCTAssertGreaterThanOrEqual(candidatos[indice - 1].confianza, candidatos[indice].confianza)
        }
    }

    func testMotorDescartaGraduacionDistinta() {
        let lectura = LecturaEtiqueta(textoCompleto: "SANTA ANA Malbec Reserva 750 ml 12 % vol",
                                      lineas: ["SANTA ANA", "Malbec Reserva", "750 ml"],
                                      marca: "Santa Ana",
                                      nombre: "Malbec Reserva",
                                      volumenML: 750,
                                      graduacion: 12)

        let variante = variantePrueba(nombre: "Vino Malbec Reserva", marca: "Santa Ana", volumen: 750, graduacion: 20)
        let candidatos = MotorCoincidencia.candidatos(lectura: lectura, colorHex: nil, variantes: [variante])
        XCTAssertFalse(candidatos.contains { $0.varianteId == variante.id })
    }

    func testMotorUsaSimilitudVisual() {
        let lectura = LecturaEtiqueta(textoCompleto: "SANTA ANA Malbec Reserva 750 ml",
                                      lineas: ["SANTA ANA", "Malbec Reserva", "750 ml"],
                                      marca: "Santa Ana",
                                      nombre: "Malbec Reserva",
                                      volumenML: 750)

        let variante = variantePrueba(nombre: "Vino Malbec Reserva", marca: "Santa Ana", volumen: 750)
        let candidatos = MotorCoincidencia.candidatos(lectura: lectura,
                                                       colorHex: nil,
                                                       variantes: [variante],
                                                       similitudesVisuales: [variante.id: 0.9])
        XCTAssertTrue(candidatos.first?.detalleCoincidencias.contains("Parecido visual") ?? false)
        XCTAssertTrue(candidatos.first?.fuentes.contains(.similitudVisual) ?? false)
    }

    func testMotorProponeProductoNuevo() {
        let lectura = LecturaEtiqueta(textoCompleto: "VINA INEXISTENTE 750 ml",
                                      lineas: ["VINA INEXISTENTE", "750 ml"],
                                      marca: "Vina Inexistente",
                                      nombre: "Vino Inexistente",
                                      volumenML: 750)

        let candidatos = MotorCoincidencia.candidatos(lectura: lectura, colorHex: nil, variantes: [])
        XCTAssertEqual(candidatos.count, 1)
        XCTAssertTrue(candidatos.first?.esNuevo ?? false)
        XCTAssertEqual(candidatos.first?.volumenML, 750)
        XCTAssertEqual(candidatos.first?.confianza ?? 0, 0.30, accuracy: 0.001)
    }

    func testSugerenciasNuevas() {
        let lectura = LecturaEtiqueta(textoCompleto: "VINA INEXISTENTE 750 ml",
                                      lineas: ["VINA INEXISTENTE", "750 ml"],
                                      marca: "Vina Inexistente",
                                      nombre: "Vino Inexistente",
                                      volumenML: 750)

        let sugerencias = MotorCoincidencia.sugerenciasNuevas(lectura: lectura, variantes: [])
        XCTAssertEqual(sugerencias.count, 1)
        XCTAssertEqual(sugerencias.first?.volumenML, 750)
        XCTAssertEqual(sugerencias.first?.marca, "Vina Inexistente")
    }

    func testInferirTipo() {
        XCTAssertEqual(MotorCoincidencia.inferirTipo(texto: "Vino Espumoso Brut"), "Espumoso")
        XCTAssertEqual(MotorCoincidencia.inferirTipo(texto: "Vino Rosado"), "Rosado")
        XCTAssertEqual(MotorCoincidencia.inferirTipo(texto: "Vino Blanco"), "Blanco")
        XCTAssertEqual(MotorCoincidencia.inferirTipo(texto: "Vino Tinto"), "Tinto")
        XCTAssertEqual(MotorCoincidencia.inferirTipo(texto: "Whisky"), "")
    }

    // MARK: - Color

    func testSimilitudColor() {
        XCTAssertGreaterThan(AnalizadorColor.similitud("#8B1E3F", "#8B1E3F"), 0.8)
        XCTAssertLessThan(AnalizadorColor.similitud("#FF0000", "#0000FF"), 0.5)
        XCTAssertEqual(AnalizadorColor.similitud(nil, "#FF0000"), 0)
        XCTAssertEqual(AnalizadorColor.similitud("#FF0000", nil), 0)
        XCTAssertEqual(AnalizadorColor.similitud(nil, nil), 0)
    }

    func testSimilitudColorIgnoraNegroYBlanco() {
        XCTAssertEqual(AnalizadorColor.similitud("#000000", "#123456"), 0)
        XCTAssertEqual(AnalizadorColor.similitud("#FFFFFF", "#123456"), 0)
    }

    // MARK: - Auxiliares

    private func variantePrueba(nombre: String,
                                marca: String,
                                volumen: Int,
                                graduacion: Double = 13.5,
                                codigo: String? = nil) -> VarianteInfo {
        VarianteInfo(id: UUID(),
                     productoId: UUID(),
                     nombreProducto: nombre,
                     marca: marca,
                     categoria: "Vino argentino",
                     tipo: "Tinto",
                     sabor: "",
                     volumenML: volumen,
                     graduacion: graduacion,
                     codigoBarras: codigo,
                     rutasFotos: [],
                     pais: "Argentina",
                     aciertos: 0,
                     intentos: 0)
    }
}
