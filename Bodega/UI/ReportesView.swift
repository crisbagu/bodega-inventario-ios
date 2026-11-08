import SwiftUI
import SwiftData
import Charts

// MARK: - Reportes

/// Reportes con Swift Charts: qué sale más, qué se agota y el resumen por día.
struct ReportesView: View {
    @Environment(\.modelContext) private var context

    @Query private var movimientos: [Movimiento]
    @Query private var variantes: [Variante]
    @Query private var productos: [Producto]
    @Query(sort: \Categoria.orden) private var categorias: [Categoria]

    // MARK: - Datos derivados

    private var movimientosVivos: [Movimiento] {
        movimientos.filter { !$0.anulado }
    }

    private func nombreProducto(para varianteId: UUID) -> String {
        guard let variante = variantes.first(where: { $0.id == varianteId }) else { return "Producto" }
        return productos.first { $0.id == variante.productoId }?.nombre ?? "Producto"
    }

    /// Unidades que salen por producto.
    private var salidasPorProducto: [(nombre: String, valor: Int)] {
        var acumulado: [String: Int] = [:]
        for movimiento in movimientosVivos where movimiento.tipo == .salida {
            let nombre = nombreProducto(para: movimiento.varianteId)
            acumulado[nombre, default: 0] += movimiento.cantidad
        }
        return acumulado.map { (nombre: $0.key, valor: $0.value) }
            .sorted { $0.valor > $1.valor }
    }

    /// Unidades que entran por producto.
    private var entradasPorProducto: [(nombre: String, valor: Int)] {
        var acumulado: [String: Int] = [:]
        for movimiento in movimientosVivos where movimiento.tipo == .entrada {
            let nombre = nombreProducto(para: movimiento.varianteId)
            acumulado[nombre, default: 0] += movimiento.cantidad
        }
        return acumulado.map { (nombre: $0.key, valor: $0.value) }
            .sorted { $0.valor > $1.valor }
    }

    private var stockPorProducto: [(nombre: String, stock: Int, minimo: Int)] {
        var resultado: [(nombre: String, stock: Int, minimo: Int)] = []
        for producto in productos {
            let variantesProducto = variantes.filter { $0.productoId == producto.id }
            guard !variantesProducto.isEmpty else { continue }
            let stock = variantesProducto.reduce(0) { $0 + Inventario.stock(varianteId: $1.id, context: context) }
            let minimo = variantesProducto.reduce(0) { $0 + $1.stockMinimo }
            resultado.append((nombre: producto.nombre, stock: stock, minimo: minimo))
        }
        return resultado.sorted { $0.stock < $1.stock }
    }

    /// Resumen de los últimos 7 días: entradas y salidas por día.
    private var resumenDiario: [PuntoDia] {
        var puntos: [PuntoDia] = []
        let calendario = Calendar.current
        for offset in stride(from: 6, through: 0, by: -1) {
            guard let dia = calendario.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            let delDia = movimientosVivos.filter { calendario.isDate($0.fecha, inSameDayAs: dia) }
            let entradas = delDia.filter { $0.tipo == .entrada }.reduce(0) { $0 + $1.cantidad }
            let salidas = delDia.filter { $0.tipo == .salida }.reduce(0) { $0 + $1.cantidad }
            puntos.append(PuntoDia(dia: etiquetaDia(dia), entradas: entradas, salidas: salidas))
        }
        return puntos
    }

    private func etiquetaDia(_ fecha: Date) -> String {
        let formato = DateFormatter()
        formato.locale = Locale(identifier: "es_ES")
        formato.dateFormat = "EEE"
        return formato.string(from: fecha).capitalized
    }

    private var sinDatos: Bool {
        movimientos.isEmpty
    }

    // MARK: - Cuerpo

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Espaciado.grande) {
                    if sinDatos {
                        VacioEstado(emoji: "📊",
                                    titulo: "Todavía no hay datos",
                                    mensaje: "Registrá entradas y salidas y los reportes se arman solos.")
                    } else {
                        seccionResumenDiario
                        seccionMasSalen
                        seccionMenosSalen
                        seccionAgotando
                    }
                }
                .padding(Espaciado.grande)
            }
            .background(Color.fondo)
            .navigationTitle("Reportes 📊")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Resumen diario

    private var seccionResumenDiario: some View {
        VStack(alignment: .leading, spacing: Espaciado.medio) {
            Text("📅 Últimos 7 días")
                .font(.titulo)
                .foregroundStyle(Color.textoPrimario)

            Chart {
                ForEach(resumenDiario) { punto in
                    BarMark(
                        x: .value("Día", punto.dia),
                        y: .value("Entradas", punto.entradas)
                    )
                    .foregroundStyle(Color.exito.gradient)
                    .position(by: .value("Tipo", "Entradas"))

                    BarMark(
                        x: .value("Día", punto.dia),
                        y: .value("Salidas", punto.salidas)
                    )
                    .foregroundStyle(Color.aviso.gradient)
                    .position(by: .value("Tipo", "Salidas"))
                }
            }
            .chartForegroundStyleScale([
                "Entradas": Color.exito,
                "Salidas": Color.aviso
            ])
            .chartLegend(position: .bottom, alignment: .leading)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 220)

            HStack(spacing: Espaciado.medio) {
                TarjetaResumen(emoji: "📥",
                               titulo: "Entradas (7 días)",
                               valor: "\(resumenDiario.reduce(0) { $0 + $1.entradas })",
                               detalle: "unidades",
                               color: .exito)
                TarjetaResumen(emoji: "📤",
                               titulo: "Salidas (7 días)",
                               valor: "\(resumenDiario.reduce(0) { $0 + $1.salidas })",
                               detalle: "unidades",
                               color: .aviso)
            }
        }
        .tarjeta()
    }

    // MARK: - Más y menos salidas

    private var seccionMasSalen: some View {
        let puntos = salidasPorProducto.prefix(8).map { PuntoProducto(nombre: $0.nombre, valor: $0.valor) }
        return graficoTitulo(titulo: "🔥 Lo que más sale",
                             subtitulo: "Unidades salidas por producto",
                             puntos: Array(puntos),
                             color: .acento)
    }

    private var seccionMenosSalen: some View {
        let puntos = Array(salidasPorProducto.suffix(8).reversed())
        let sinSalidas = entradasPorProducto
            .filter { entrada in !salidasPorProducto.contains { $0.nombre == entrada.nombre } }
            .map { (nombre: $0.nombre, valor: 0) }
        let combinados = (puntos + sinSalidas)
            .sorted { $0.valor < $1.valor }
            .prefix(8)
            .map { PuntoProducto(nombre: $0.nombre, valor: $0.valor) }
        return graficoTitulo(titulo: "🧊 Lo que menos sale",
                             subtitulo: "Productos que casi no se mueven",
                             puntos: Array(combinados),
                             color: .aviso)
    }

    private func graficoTitulo(titulo: String,
                               subtitulo: String,
                               puntos: [PuntoProducto],
                               color: Color) -> some View {
        VStack(alignment: .leading, spacing: Espaciado.medio) {
            Text(titulo)
                .font(.titulo)
                .foregroundStyle(Color.textoPrimario)
            Text(subtitulo)
                .font(.etiqueta)
                .foregroundStyle(Color.textoSecundario)

            if puntos.isEmpty {
                Text("Sin datos todavía.")
                    .font(.cuerpo)
                    .foregroundStyle(Color.textoSecundario)
                    .padding(.vertical, Espaciado.grande)
            } else {
                Chart(puntos) { punto in
                    BarMark(
                        x: .value("Unidades", punto.valor),
                        y: .value("Producto", punto.nombre)
                    )
                    .foregroundStyle(color.gradient)
                    .annotation(position: .trailing) {
                        Text("\(punto.valor)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.textoSecundario)
                    }
                }
                .chartXAxis {
                    AxisMarks { AxisGridLine(); AxisValueLabel() }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let texto = value.as(String.self) {
                                Text(texto)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                    }
                }
                .frame(height: CGFloat(max(1, puntos.count)) * 34 + 30)
            }
        }
        .tarjeta()
    }

    // MARK: - Se agotan

    private var seccionAgotando: some View {
        let puntos = stockPorProducto
            .filter { $0.minimo > 0 }
            .prefix(10)
            .map { PuntoStock(nombre: $0.nombre, stock: $0.stock, minimo: $0.minimo) }

        return VStack(alignment: .leading, spacing: Espaciado.medio) {
            Text("🫙 Se están agotando")
                .font(.titulo)
                .foregroundStyle(Color.textoPrimario)
            Text("Stock actual contra el mínimo que definiste")
                .font(.etiqueta)
                .foregroundStyle(Color.textoSecundario)

            if puntos.isEmpty {
                VacioEstado(emoji: "✅",
                            titulo: "Nada por debajo del mínimo",
                            mensaje: "Todos los productos tienen stock suficiente.")
            } else {
                Chart(puntos) { punto in
                    BarMark(
                        x: .value("Unidades", punto.stock),
                        y: .value("Producto", punto.nombre)
                    )
                    .foregroundStyle(punto.stock <= punto.minimo ? Color.peligro.gradient : Color.exito.gradient)
                    .annotation(position: .trailing) {
                        Text("\(punto.stock)/\(punto.minimo)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.textoSecundario)
                    }
                }
                .chartXAxis {
                    AxisMarks { AxisGridLine(); AxisValueLabel() }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let texto = value.as(String.self) {
                                Text(texto)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                    }
                }
                .frame(height: CGFloat(max(1, puntos.count)) * 34 + 30)
            }
        }
        .tarjeta()
    }
}

// MARK: - Puntos de los gráficos

struct PuntoProducto: Identifiable {
    let id = UUID()
    let nombre: String
    let valor: Int
}

struct PuntoDia: Identifiable {
    let id = UUID()
    let dia: String
    let entradas: Int
    let salidas: Int
}

struct PuntoStock: Identifiable {
    let id = UUID()
    let nombre: String
    let stock: Int
    let minimo: Int
}
