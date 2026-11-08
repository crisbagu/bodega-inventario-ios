import SwiftUI
import SwiftData

// MARK: - Galería de fotos

/// Fotos agrupadas por producto, en orden alfabético.
struct GaleriaFotosView: View {
    @Query private var productos: [Producto]
    @Query private var variantes: [Variante]
    @Query private var movimientos: [Movimiento]
    @Query(sort: \Categoria.orden) private var categorias: [Categoria]

    @State private var fotoAmplia: IdentificadorFoto? = nil

    private var grupos: [GrupoFotos] {
        let ordenados = productos.sorted {
            $0.nombre.localizedCaseInsensitiveCompare($1.nombre) == .orderedAscending
        }
        var resultado: [GrupoFotos] = []
        for producto in ordenados {
            let rutas = Set(variantes.filter { $0.productoId == producto.id }.flatMap { $0.rutasFotos })
            guard !rutas.isEmpty else { continue }
            let ordenadas = rutas.sorted { (fechaDeFoto($0) ?? .distantPast) > (fechaDeFoto($1) ?? .distantPast) }
            resultado.append(GrupoFotos(producto: producto, fotos: ordenadas))
        }
        return resultado
    }

    private var totalFotos: Int {
        grupos.reduce(0) { $0 + $1.fotos.count }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Espaciado.grande) {
                    if grupos.isEmpty {
                        VacioEstado(emoji: "📷",
                                    titulo: "Todavía no hay fotos",
                                    mensaje: "Cada vez que registrás una entrada o salida, la foto queda guardada acá.")
                    } else {
                        ForEach(grupos, id: \.producto.id) { grupo in
                            tarjetaGrupo(grupo)
                        }
                    }
                }
                .padding(Espaciado.grande)
            }
            .background(Color.fondo)
            .navigationTitle("Fotos 🖼️")
            .navigationBarTitleDisplayMode(.large)
            .fullScreenCover(item: $fotoAmplia) { item in
                VistaFotoAmplia(ruta: item.ruta,
                                movimiento: movimientoDeFoto(item.ruta),
                                producto: productoDeFoto(item.ruta))
            }
        }
    }

    // MARK: - Tarjeta de grupo

    private func tarjetaGrupo(_ grupo: GrupoFotos) -> some View {
        VStack(alignment: .leading, spacing: Espaciado.medio) {
            NavigationLink {
                DetalleProductoView(productoId: grupo.producto.id)
            } label: {
                HStack(spacing: Espaciado.medio) {
                    Text(emojiProducto(grupo.producto)).font(.system(size: 26))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(grupo.producto.nombre)
                            .font(.subtitulo)
                            .foregroundStyle(Color.textoPrimario)
                            .lineLimit(1)
                        Text("\(grupo.fotos.count) foto\(grupo.fotos.count == 1 ? "" : "s")")
                            .font(.etiqueta)
                            .foregroundStyle(Color.textoSecundario)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.etiqueta.weight(.bold))
                        .foregroundStyle(Color.acento)
                }
            }
            .buttonStyle(.plain)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Espaciado.chico) {
                    ForEach(grupo.fotos, id: \.self) { ruta in
                        Button {
                            fotoAmplia = IdentificadorFoto(ruta: ruta)
                        } label: {
                            MiniaturaFoto(ruta: ruta, lado: 104, radio: Radio.medio)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .tarjeta()
    }

    // MARK: - Utilidades

    private func categoriaDe(_ producto: Producto) -> Categoria? {
        guard let id = producto.categoriaId else { return nil }
        return categorias.first { $0.id == id }
    }

    private func emojiProducto(_ producto: Producto) -> String {
        emojiDeCategoria(categoria: categoriaDe(producto), tipo: producto.nombre)
    }

    private func movimientoDeFoto(_ ruta: String) -> Movimiento? {
        movimientos.first { $0.fotoRuta == ruta }
    }

    private func productoDeFoto(_ ruta: String) -> Producto? {
        guard let varianteId = movimientoDeFoto(ruta)?.varianteId,
              let variante = variantes.first(where: { $0.id == varianteId }) else { return nil }
        return productos.first { $0.id == variante.productoId }
    }

    private func fechaDeFoto(_ ruta: String) -> Date? {
        movimientoDeFoto(ruta)?.fecha
    }
}

// MARK: - Grupo de fotos

struct GrupoFotos: Identifiable {
    let producto: Producto
    let fotos: [String]
    var id: UUID { producto.id }
}

// MARK: - Foto a pantalla completa

/// Vista ampliada de una foto con su fecha, su usuario y su movimiento.
struct VistaFotoAmplia: View {
    let ruta: String
    var movimiento: Movimiento? = nil
    var producto: Producto? = nil

    @Environment(\.dismiss) private var cerrar

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: Espaciado.grande) {
                Spacer(minLength: 0)

                if let cg = AlmacenFotos.compartido.imagen(paraRuta: ruta) {
                    Image(decorative: cg, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .padding(Espaciado.medio)
                } else {
                    Text("🖼️").font(.system(size: 64))
                }

                VStack(spacing: Espaciado.chico) {
                    if let producto {
                        Text(producto.nombre)
                            .font(.titulo)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                    }
                    if let movimiento {
                        Text("\(movimiento.tipo.emoji) \(movimiento.tipo.titulo) · \(movimiento.cantidad)")
                            .font(.subtitulo)
                            .foregroundStyle(.white.opacity(0.85))
                        Text("\(fecha(movimiento.fecha)) · \(movimiento.usuario)")
                            .font(.etiqueta)
                            .foregroundStyle(.white.opacity(0.7))
                        if !movimiento.nota.isEmpty {
                            Text(movimiento.nota)
                                .font(.etiqueta)
                                .foregroundStyle(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .padding(.horizontal, Espaciado.grande)

                Spacer(minLength: 0)

                Button {
                    cerrar()
                } label: {
                    Text("✖️ Cerrar")
                        .font(.subtitulo)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Espaciado.grande)
                        .frame(minHeight: DesignSystem.altoBoton)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.bottom, Espaciado.grande)
            }
        }
    }

    private func fecha(_ valor: Date) -> String {
        let formato = DateFormatter()
        formato.locale = Locale(identifier: "es_ES")
        formato.dateFormat = "d MMM yyyy · HH:mm"
        return formato.string(from: valor)
    }
}
