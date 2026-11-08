import SwiftUI
import SwiftData

// MARK: - Lista de productos

/// Todos los productos en orden alfabético, con buscador y filtros.
struct ListaProductosView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \Producto.nombre) private var productos: [Producto]
    @Query private var variantes: [Variante]
    @Query private var movimientos: [Movimiento]
    @Query(sort: \Categoria.orden) private var categorias: [Categoria]

    @State private var busqueda: String = ""
    @State private var filtroCategoria: UUID? = nil
    @State private var filtroVolumen: Int? = nil
    @State private var filtroMarca: String? = nil
    @State private var filtroFecha: RangoFecha = .todo
    @State private var mostrarFiltros: Bool = false
    @State private var productoARenombrar: Producto? = nil
    @State private var nuevoNombre: String = ""
    @State private var productoABorrar: Producto? = nil
    @State private var avisoUnidad: Int = 0

    private var esAdmin: Bool { Preferencias.rolActual == .administrador }

    // MARK: - Filtros

    private var categoriasDisponibles: [Categoria] { categorias }

    private var volumenesDisponibles: [Int] {
        Array(Set(variantes.map { $0.volumenML })).sorted()
    }

    private var marcasDisponibles: [String] {
        Array(Set(productos.map { $0.marca })).sorted()
    }

    private var cutoffFecha: Date {
        switch filtroFecha {
        case .siete:
            return Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        case .treinta:
            return Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        case .todo:
            return Date.distantPast
        }
    }

    private var variantesEnPeriodo: Set<UUID> {
        var ids = Set<UUID>()
        for movimiento in movimientos where !movimiento.anulado && movimiento.fecha >= cutoffFecha {
            ids.insert(movimiento.varianteId)
        }
        return ids
    }

    private var productosFiltrados: [Producto] {
        let texto = busqueda.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return productos.filter { producto in
            // Texto
            if !texto.isEmpty {
                let coincide = producto.nombre.lowercased().contains(texto)
                    || producto.marca.lowercased().contains(texto)
                if !coincide { return false }
            }
            // Categoría
            if let filtroCategoria, producto.categoriaId != filtroCategoria { return false }
            // Marca
            if let filtroMarca, producto.marca != filtroMarca { return false }
            // Tamaño (alguna variante con ese volumen)
            if let filtroVolumen {
                let variantesDelProducto = variantes.filter { $0.productoId == producto.id }
                if !variantesDelProducto.contains(where: { $0.volumenML == filtroVolumen }) { return false }
            }
            // Fecha
            if filtroFecha != .todo {
                let variantesDelProducto = variantes.filter { $0.productoId == producto.id }
                if !variantesDelProducto.contains(where: { variantesEnPeriodo.contains($0.id) }) { return false }
            }
            return true
        }
        .sorted { $0.nombre.localizedCaseInsensitiveCompare($1.nombre) == .orderedAscending }
    }

    private var cantidadFiltrosActivos: Int {
        var total = 0
        if filtroCategoria != nil { total += 1 }
        if filtroVolumen != nil { total += 1 }
        if filtroMarca != nil { total += 1 }
        if filtroFecha != .todo { total += 1 }
        return total
    }

    // MARK: - Cuerpo

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                cabecera
                if productosFiltrados.isEmpty {
                    VacioEstado(emoji: "🫙",
                                titulo: "No hay productos",
                                mensaje: "Registrá entradas con la cámara o cambiá los filtros.")
                } else {
                    lista
                }
            }
            .background(Color.fondo)
            .navigationTitle("Productos 🫙")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $mostrarFiltros) {
                HojaFiltros(categoria: $filtroCategoria,
                            volumen: $filtroVolumen,
                            marca: $filtroMarca,
                            fecha: $filtroFecha,
                            categorias: categoriasDisponibles,
                            volumenes: volumenesDisponibles,
                            marcas: marcasDisponibles)
            }
            .onReceive(NotificationCenter.default.publisher(for: .bodegaUnidadCambiada)) { _ in
                avisoUnidad += 1
            }
            .alert("Renombrar producto",
                   isPresented: Binding(get: { productoARenombrar != nil },
                                        set: { nuevo in if !nuevo { productoARenombrar = nil } }),
                   presenting: productoARenombrar) { producto in
                TextField("Nombre del producto", text: $nuevoNombre)
                Button("Cancelar", role: .cancel) {}
                Button("Guardar") { renombrar(producto) }
            } message: { _ in
                Text("Escribí el nombre nuevo.")
            }
            .confirmationDialog("¿Borrar \(productoABorrar?.nombre ?? "el producto")?",
                                isPresented: Binding(get: { productoABorrar != nil },
                                                     set: { nuevo in if !nuevo { productoABorrar = nil } }),
                                titleVisibility: .visible,
                                presenting: productoABorrar) { producto in
                Button("🗑️ Borrar producto y sus datos", role: .destructive) { borrar(producto) }
                Button("Cancelar", role: .cancel) {}
            } message: { _ in
                Text("Se borran también sus variantes, fotos y movimientos. No se puede deshacer.")
            }
        }
    }

    // MARK: - Cabecera con buscador y filtros

    private var cabecera: some View {
        VStack(spacing: Espaciado.medio) {
            HStack(spacing: Espaciado.medio) {
                TextField("Buscar por nombre o marca", text: $busqueda)
                    .font(.cuerpo)
                    .padding(.horizontal, Espaciado.grande)
                    .frame(minHeight: DesignSystem.altoBoton)
                    .background(Color.superficie, in: RoundedRectangle(cornerRadius: Radio.medio, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radio.medio, style: .continuous).stroke(Color.borde, lineWidth: 1))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    mostrarFiltros = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                        if cantidadFiltrosActivos > 0 {
                            Text("\(cantidadFiltrosActivos)")
                                .font(.etiqueta.weight(.bold))
                        }
                    }
                    .foregroundStyle(Color.textoSobreAcento)
                    .frame(width: 56, height: DesignSystem.altoBoton)
                    .background(Color.acento, in: RoundedRectangle(cornerRadius: Radio.medio, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Filtros")
            }

            if cantidadFiltrosActivos > 0 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Espaciado.chico) {
                        if let filtroCategoria, let categoria = categorias.first(where: { $0.id == filtroCategoria }) {
                            chipActivo(emoji: categoria.emoji, texto: categoria.nombre) { self.filtroCategoria = nil }
                        }
                        if let filtroVolumen {
                            chipActivo(emoji: "📏", texto: Unidades.texto(filtroVolumen)) { self.filtroVolumen = nil }
                        }
                        if let filtroMarca {
                            chipActivo(emoji: "🏷️", texto: filtroMarca) { self.filtroMarca = nil }
                        }
                        if filtroFecha != .todo {
                            chipActivo(emoji: "🗓️", texto: filtroFecha.titulo) { filtroFecha = .todo }
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
        .padding(.horizontal, Espaciado.grande)
        .padding(.bottom, Espaciado.medio)
    }

    private func chipActivo(emoji: String, texto: String, alQuitar: @escaping () -> Void) -> some View {
        Button(action: alQuitar) {
            HStack(spacing: 5) {
                Text(emoji).font(.system(size: 12))
                Text(texto).font(.etiqueta)
                Image(systemName: "xmark.circle.fill").font(.system(size: 12))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.acento.opacity(0.14), in: Capsule())
            .foregroundStyle(Color.acento)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Lista

    private var lista: some View {
        List {
            ForEach(productosFiltrados, id: \.id) { producto in
                NavigationLink {
                    DetalleProductoView(productoId: producto.id)
                } label: {
                    TarjetaProducto(producto: producto,
                                    emojiCategoria: emojiProducto(producto),
                                    stock: stockTotal(producto),
                                    numeroFotos: fotosTotal(producto),
                                    rutaFoto: fotoPrincipal(producto))
                        .padding(.vertical, Espaciado.chico)
                }
                .listRowBackground(Color.fondo)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if esAdmin {
                        Button {
                            nuevoNombre = producto.nombre
                            productoARenombrar = producto
                        } label: {
                            Label("Renombrar", systemImage: "pencil")
                        }
                        .tint(Color.acento)

                        Button(role: .destructive) {
                            productoABorrar = producto
                        } label: {
                            Label("Borrar", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.fondo)
    }

    // MARK: - Utilidades

    private func categoriaDe(_ producto: Producto) -> Categoria? {
        guard let id = producto.categoriaId else { return nil }
        return categorias.first { $0.id == id }
    }

    private func emojiProducto(_ producto: Producto) -> String {
        emojiDeCategoria(categoria: categoriaDe(producto), tipo: producto.nombre)
    }

    private func variantesDe(_ producto: Producto) -> [Variante] {
        variantes.filter { $0.productoId == producto.id }
    }

    private func stockTotal(_ producto: Producto) -> Int {
        variantesDe(producto).reduce(0) { $0 + Inventario.stock(varianteId: $1.id, context: context) }
    }

    private func fotosTotal(_ producto: Producto) -> Int {
        Set(variantesDe(producto).flatMap { $0.rutasFotos }).count
    }

    private func fotoPrincipal(_ producto: Producto) -> String? {
        variantesDe(producto).flatMap { $0.rutasFotos }.first
    }

    private func renombrar(_ producto: Producto) {
        let limpio = nuevoNombre.trimmingCharacters(in: .whitespacesAndNewlines)
        if !limpio.isEmpty { producto.nombre = limpio }
        try? context.save()
    }

    private func borrar(_ producto: Producto) {
        let variantesProducto = variantesDe(producto)
        let idsVariantes = Set(variantesProducto.map { $0.id })
        for movimiento in movimientos where idsVariantes.contains(movimiento.varianteId) {
            context.delete(movimiento)
        }
        for variante in variantesProducto {
            for ruta in variante.rutasFotos {
                AlmacenFotos.compartido.borrar(ruta: ruta)
            }
            context.delete(variante)
        }
        context.delete(producto)
        try? context.save()
        Retroalimentacion.exito()
    }
}

// MARK: - Rango de fechas

/// Filtro por fecha de los últimos movimientos.
enum RangoFecha: Int, CaseIterable, Identifiable {
    case siete
    case treinta
    case todo

    var id: Int { rawValue }

    var titulo: String {
        switch self {
        case .siete: return "Últimos 7 días"
        case .treinta: return "Últimos 30 días"
        case .todo: return "Todo"
        }
    }

    var emoji: String {
        switch self {
        case .siete: return "🗓️"
        case .treinta: return "📆"
        case .todo: return "🗃️"
        }
    }
}

// MARK: - Hoja de filtros

/// Hoja con todos los filtros de la lista de productos.
struct HojaFiltros: View {
    @Binding var categoria: UUID?
    @Binding var volumen: Int?
    @Binding var marca: String?
    @Binding var fecha: RangoFecha

    let categorias: [Categoria]
    let volumenes: [Int]
    let marcas: [String]

    @Environment(\.dismiss) private var cerrar

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Espaciado.grande) {
                    grupo("🗂️ Categoría") {
                        filaChips(categorias.map { ($0.emoji, $0.nombre, $0.id) }) { id in
                            categoria = (categoria == id) ? nil : id
                        } seleccionado: { id in categoria == id }
                    }

                    grupo("📏 Tamaño") {
                        filaChips(volumenes.map { ("📐", Unidades.texto($0), $0) }) { id in
                            volumen = (volumen == id) ? nil : id
                        } seleccionado: { id in volumen == id }
                    }

                    grupo("🏷️ Marca") {
                        filaChips(marcas.map { ("🏷️", $0, $0) }) { id in
                            marca = (marca == id) ? nil : id
                        } seleccionado: { id in marca == id }
                    }

                    grupo("🗓️ Fecha") {
                        VStack(alignment: .leading, spacing: Espaciado.chico) {
                            ForEach(RangoFecha.allCases) { rango in
                                Button {
                                    fecha = rango
                                } label: {
                                    HStack {
                                        Text(rango.emoji)
                                        Text(rango.titulo).font(.cuerpo)
                                        Spacer()
                                        if fecha == rango {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(Color.acento)
                                        }
                                    }
                                    .foregroundStyle(Color.textoPrimario)
                                    .padding(.vertical, Espaciado.chico)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    BotonGrande(titulo: "Limpiar filtros",
                                emoji: "🧹",
                                estilo: .neutro,
                                alto: 56) {
                        categoria = nil
                        volumen = nil
                        marca = nil
                        fecha = .todo
                    }
                }
                .padding(Espaciado.grande)
            }
            .background(Color.fondo)
            .navigationTitle("Filtros")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { cerrar() }
                        .font(.subtitulo.weight(.semibold))
                }
            }
        }
    }

    private func grupo<Content: View>(_ titulo: String, @ViewBuilder contenido: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Espaciado.medio) {
            Text(titulo)
                .font(.subtitulo)
                .foregroundStyle(Color.textoPrimario)
            contenido()
        }
    }

    private func filaChips<T: Hashable>(_ items: [(emoji: String, texto: String, id: T)],
                                        alElegir: @escaping (T) -> Void,
                                        seleccionado: @escaping (T) -> Bool) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: Espaciado.chico)], spacing: Espaciado.chico) {
            ForEach(items, id: \.id) { item in
                Button {
                    alElegir(item.id)
                } label: {
                    HStack(spacing: 6) {
                        Text(item.emoji).font(.system(size: 13))
                        Text(item.texto)
                            .font(.etiqueta)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if seleccionado(item.id) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                        }
                    }
                    .foregroundStyle(seleccionado(item.id) ? Color.acento : Color.textoPrimario)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(seleccionado(item.id) ? Color.acento.opacity(0.14) : Color.superficie,
                                in: RoundedRectangle(cornerRadius: Radio.suave, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
