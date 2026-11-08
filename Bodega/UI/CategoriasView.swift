import SwiftUI
import SwiftData

// MARK: - Categorías

/// Alta, renombrado, reordenado y borrado de categorías.
struct CategoriasView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \Categoria.orden) private var categorias: [Categoria]
    @Query private var productos: [Producto]

    @State private var aviso: AvisoCategoria? = nil
    @State private var nuevoNombre: String = ""
    @State private var nuevoEmoji: String = "📦"
    @State private var categoriaARenombrar: Categoria? = nil
    @State private var categoriaABorrar: Categoria? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Espaciado.grande) {
                    if categorias.isEmpty {
                        VacioEstado(emoji: "🗂️",
                                    titulo: "No hay categorías",
                                    mensaje: "Creá la primera para ordenar tu bodega.")
                    } else {
                        VStack(spacing: Espaciado.chico) {
                            ForEach(categorias, id: \.id) { categoria in
                                fila(categoria)
                            }
                        }
                        .tarjeta()
                    }

                    BotonGrande(titulo: "Crear categoría",
                                emoji: "➕",
                                estilo: .acento,
                                alto: 60) {
                        nuevoNombre = ""
                        nuevoEmoji = "📦"
                        aviso = .crear
                    }
                }
                .padding(Espaciado.grande)
            }
            .background(Color.fondo)
            .navigationTitle("Categorías 🗂️")
            .navigationBarTitleDisplayMode(.inline)
            .alert(aviso?.titulo ?? "",
                   isPresented: Binding(get: { aviso != nil },
                                        set: { nuevo in if !nuevo { aviso = nil } }),
                   presenting: aviso) { aviso in
                switch aviso {
                case .renombrar:
                    TextField("Nombre", text: $nuevoNombre)
                    Button("Cancelar", role: .cancel) {}
                    Button("Guardar") { renombrar() }
                case .crear:
                    TextField("Nombre", text: $nuevoNombre)
                    TextField("Emoji", text: $nuevoEmoji)
                    Button("Cancelar", role: .cancel) {}
                    Button("Crear") { crear() }
                case .borrar:
                    Button("Cancelar", role: .cancel) {}
                    Button("Borrar", role: .destructive) { borrar() }
                }
            } message: { aviso in
                Text(aviso.mensaje)
            }
        }
    }

    // MARK: - Fila

    private func fila(_ categoria: Categoria) -> some View {
        let cantidad = productos.filter { $0.categoriaId == categoria.id }.count

        return HStack(spacing: Espaciado.medio) {
            Text(categoria.emoji.isEmpty ? "📦" : categoria.emoji)
                .font(.system(size: 26))
                .frame(width: 44, height: 44)
                .background(Color.superficieElevada, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(categoria.nombre)
                    .font(.subtitulo)
                    .foregroundStyle(Color.textoPrimario)
                Text("\(cantidad) producto\(cantidad == 1 ? "" : "s")")
                    .font(.etiqueta)
                    .foregroundStyle(Color.textoSecundario)
            }

            Spacer(minLength: 0)

            Menu {
                Button {
                    mover(categoria, arriba: true)
                } label: {
                    Label("Subir", systemImage: "arrow.up")
                }
                Button {
                    mover(categoria, arriba: false)
                } label: {
                    Label("Bajar", systemImage: "arrow.down")
                }
                Button {
                    nuevoNombre = categoria.nombre
                    nuevoEmoji = categoria.emoji
                    categoriaARenombrar = categoria
                    aviso = .renombrar
                } label: {
                    Label("Renombrar", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    categoriaABorrar = categoria
                    aviso = .borrar
                } label: {
                    Label("Borrar", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.acento)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Opciones de \(categoria.nombre)")
        }
        .padding(.vertical, Espaciado.chico)
    }

    // MARK: - Acciones

    private func mover(_ categoria: Categoria, arriba: Bool) {
        let ordenadas = categorias
        guard let indice = ordenadas.firstIndex(where: { $0.id == categoria.id }) else { return }
        let destino = arriba ? indice - 1 : indice + 1
        guard destino >= 0, destino < ordenadas.count else { return }

        let actual = ordenadas[indice]
        let vecino = ordenadas[destino]
        let ordenActual = actual.orden
        actual.orden = vecino.orden
        vecino.orden = ordenActual
        try? context.save()
        Retroalimentacion.exito()
    }

    private func renombrar() {
        guard let categoria = categoriaARenombrar else { return }
        let limpio = nuevoNombre.trimmingCharacters(in: .whitespacesAndNewlines)
        if !limpio.isEmpty { categoria.nombre = limpio }
        let emoji = nuevoEmoji.trimmingCharacters(in: .whitespacesAndNewlines)
        if !emoji.isEmpty { categoria.emoji = emoji }
        try? context.save()
        Retroalimentacion.exito()
    }

    private func crear() {
        let limpio = nuevoNombre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty else { return }
        let emoji = nuevoEmoji.trimmingCharacters(in: .whitespacesAndNewlines)
        let nueva = Categoria(nombre: limpio,
                              emoji: emoji.isEmpty ? "📦" : emoji,
                              orden: (categorias.map { $0.orden }.max() ?? 0) + 1)
        context.insert(nueva)
        try? context.save()
        Retroalimentacion.exito()
    }

    private func borrar() {
        guard let categoria = categoriaABorrar else { return }
        context.delete(categoria)
        try? context.save()
        Retroalimentacion.aviso()
    }
}

// MARK: - Avisos de categorías

enum AvisoCategoria: Identifiable {
    case renombrar
    case crear
    case borrar

    var id: String {
        switch self {
        case .renombrar: return "renombrar"
        case .crear: return "crear"
        case .borrar: return "borrar"
        }
    }

    var titulo: String {
        switch self {
        case .renombrar: return "Renombrar categoría"
        case .crear: return "Nueva categoría"
        case .borrar: return "¿Borrar la categoría?"
        }
    }

    var mensaje: String {
        switch self {
        case .renombrar: return "Escribí el nombre nuevo. Podés cambiar el emoji también."
        case .crear: return "Escribí el nombre y el emoji (por ejemplo 🍷)."
        case .borrar: return "Los productos quedan sin categoría. No se borran."
        }
    }
}
