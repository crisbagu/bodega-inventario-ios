import SwiftUI
import SwiftData

// MARK: - Movimientos

/// Historial de movimientos: hoy o la fecha elegida, con filtro por tipo.
struct MovimientosView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \Movimiento.fecha, order: .reverse) private var movimientos: [Movimiento]
    @Query private var variantes: [Variante]
    @Query private var productos: [Producto]

    @State private var fecha: Date = Date()
    @State private var filtroTipo: FiltroTipo = .todos

    private var esHoy: Bool {
        Calendar.current.isDateInToday(fecha)
    }

    private var movimientosFiltrados: [Movimiento] {
        movimientos.filter { movimiento in
            let mismoDia = Calendar.current.isDate(movimiento.fecha, inSameDayAs: fecha)
            guard mismoDia else { return false }
            switch filtroTipo {
            case .todos: return true
            case .entrada: return movimiento.tipo == .entrada
            case .salida: return movimiento.tipo == .salida
            }
        }
    }

    private var totalEntradas: Int {
        movimientosFiltrados.filter { $0.tipo == .entrada }.reduce(0) { $0 + $1.cantidad }
    }

    private var totalSalidas: Int {
        movimientosFiltrados.filter { $0.tipo == .salida }.reduce(0) { $0 + $1.cantidad }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                cabecera
                if movimientosFiltrados.isEmpty {
                    VacioEstado(emoji: "🗓️",
                                titulo: "Sin movimientos ese día",
                                mensaje: "No hay entradas ni salidas registradas para esa fecha.")
                } else {
                    lista
                }
            }
            .background(Color.fondo)
            .navigationTitle("Movimientos 🧾")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Cabecera

    private var cabecera: some View {
        VStack(spacing: Espaciado.medio) {
            HStack(spacing: Espaciado.medio) {
                Button {
                    fecha = Date()
                } label: {
                    Text("Hoy")
                        .font(.subtitulo.weight(.semibold))
                        .foregroundStyle(esHoy ? Color.textoSobreAcento : Color.textoPrimario)
                        .padding(.horizontal, Espaciado.grande)
                        .frame(minHeight: 48)
                        .background(esHoy ? Color.acento : Color.superficieElevada, in: Capsule())
                }
                .buttonStyle(.plain)

                DatePicker("Fecha", selection: $fecha, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(Color.acento)
                    .padding(.horizontal, Espaciado.medio)
                    .frame(minHeight: 48)
                    .background(Color.superficieElevada, in: Capsule())

                Spacer(minLength: 0)
            }

            Picker("Tipo", selection: $filtroTipo) {
                ForEach(FiltroTipo.allCases) { filtro in
                    Text(filtro.titulo).tag(filtro)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: Espaciado.medio) {
                TarjetaResumen(emoji: "📥",
                               titulo: "Entradas",
                               valor: "\(totalEntradas)",
                               detalle: "\(movimientosFiltrados.filter { $0.tipo == .entrada }.count) movs.",
                               color: .exito)
                TarjetaResumen(emoji: "📤",
                               titulo: "Salidas",
                               valor: "\(totalSalidas)",
                               detalle: "\(movimientosFiltrados.filter { $0.tipo == .salida }.count) movs.",
                               color: .aviso)
            }
        }
        .padding(.horizontal, Espaciado.grande)
        .padding(.bottom, Espaciado.medio)
    }

    // MARK: - Lista

    private var lista: some View {
        List {
            ForEach(movimientosFiltrados, id: \.id) { movimiento in
                FilaMovimiento(fotoRuta: movimiento.fotoRuta,
                               hora: hora(movimiento.fecha),
                               usuario: movimiento.usuario,
                               producto: nombre(movimiento.varianteId),
                               cantidad: movimiento.cantidad,
                               tipo: movimiento.tipo,
                               anulado: movimiento.anulado,
                               motivoAnulacion: movimiento.motivoAnulacion,
                               nota: movimiento.nota)
                    .padding(.vertical, Espaciado.chico)
                    .listRowBackground(Color.fondo)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.fondo)
    }

    // MARK: - Utilidades

    private func hora(_ valor: Date) -> String {
        let formato = DateFormatter()
        formato.locale = Locale(identifier: "es_ES")
        formato.dateFormat = "HH:mm"
        return formato.string(from: valor)
    }

    private func nombre(_ varianteId: UUID) -> String {
        guard let variante = variantes.first(where: { $0.id == varianteId }) else { return "Producto" }
        let nombreProducto = productos.first { $0.id == variante.productoId }?.nombre ?? "Producto"
        return "\(nombreProducto) · \(Unidades.texto(variante.volumenML))"
    }
}

// MARK: - Filtro por tipo

enum FiltroTipo: String, CaseIterable, Identifiable {
    case todos
    case entrada
    case salida

    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .todos: return "Todos"
        case .entrada: return "Entradas"
        case .salida: return "Salidas"
        }
    }

    var emoji: String {
        switch self {
        case .todos: return "🗂️"
        case .entrada: return "📥"
        case .salida: return "📤"
        }
    }
}
