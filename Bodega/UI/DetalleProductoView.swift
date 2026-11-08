import SwiftUI
import SwiftData

// MARK: - Detalle de producto

/// Ficha de un producto: sus variantes, sus fotos y su línea de tiempo de movimientos.
struct DetalleProductoView: View {
    let productoId: UUID

    @Environment(\.modelContext) private var context

    @Query private var productos: [Producto]
    @Query private var variantes: [Variante]
    @Query private var movimientos: [Movimiento]
    @Query(sort: \Categoria.orden) private var categorias: [Categoria]

    @State private var movimientoAAnular: Movimiento? = nil
    @State private var motivoAnulacion: String = ""
    @State private var fotoAmplia: String? = nil
    @State private var avisoUnidad: Int = 0

    // MARK: - Datos

    private var producto: Producto? {
        productos.first { $0.id == productoId }
    }

    private var categoria: Categoria? {
        guard let id = producto?.categoriaId else { return nil }
        return categorias.first { $0.id == id }
    }

    private var variantesProducto: [Variante] {
        variantes.filter { $0.productoId == productoId }.sorted { $0.volumenML < $1.volumenML }
    }

    private var movimientosProducto: [Movimiento] {
        let ids = Set(variantesProducto.map { $0.id })
        return movimientos
            .filter { ids.contains($0.varianteId) }
            .sorted { $0.fecha > $1.fecha }
    }

    private var ultimoMovimiento: Movimiento? {
        movimientosProducto.first { !$0.anulado }
    }

    private var stockTotal: Int {
        variantesProducto.reduce(0) { $0 + Inventario.stock(varianteId: $1.id, context: context) }
    }

    private var fotosTotales: Int {
        Set(variantesProducto.flatMap { $0.rutasFotos }).count
    }

    // MARK: - Cuerpo

    var body: some View {
        ScrollView {
            VStack(spacing: Espaciado.grande) {
                cabecera

                if variantesProducto.isEmpty {
                    VacioEstado(emoji: "🫙",
                                titulo: "Este producto no tiene variantes",
                                mensaje: "Registrá una entrada para crearla.")
                } else {
                    VStack(alignment: .leading, spacing: Espaciado.medio) {
                        Text("🧾 Variantes")
                            .font(.titulo)
                            .foregroundStyle(Color.textoPrimario)

                        ForEach(variantesProducto, id: \.id) { variante in
                            TarjetaVariante(variante: variante,
                                            producto: producto,
                                            categoria: categoria,
                                            alVerFoto: { fotoAmplia = $0 })
                        }
                    }
                }

                seccionMovimientos
            }
            .padding(Espaciado.grande)
        }
        .background(Color.fondo)
        .navigationTitle(producto?.nombre ?? "Producto")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(get: { fotoAmplia.map { IdentificadorFoto(ruta: $0) } },
                              set: { nuevo in fotoAmplia = nuevo?.ruta })) { item in
            VistaFotoAmplia(ruta: item.ruta,
                            movimiento: movimientoDeFoto(item.ruta),
                            producto: producto)
        }
        .alert("Anular movimiento",
               isPresented: Binding(get: { movimientoAAnular != nil },
                                    set: { nuevo in if !nuevo { movimientoAAnular = nil } }),
               presenting: movimientoAAnular) { movimiento in
            TextField("Motivo", text: $motivoAnulacion)
            Button("Cancelar", role: .cancel) {}
            Button("Anular", role: .destructive) {
                Inventario.anular(movimientoId: movimiento.id, motivo: motivoAnulacion, context: context)
                motivoAnulacion = ""
                Retroalimentacion.aviso()
            }
        } message: { _ in
            Text("El movimiento queda marcado como anulado. El historial no se borra.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .bodegaUnidadCambiada)) { _ in
            avisoUnidad += 1
        }
    }

    // MARK: - Cabecera

    private var cabecera: some View {
        VStack(alignment: .leading, spacing: Espaciado.medio) {
            HStack(spacing: Espaciado.medio) {
                Text(emojiDeCategoria(categoria: categoria, tipo: producto?.nombre ?? ""))
                    .font(.system(size: 44))
                VStack(alignment: .leading, spacing: 3) {
                    Text(producto?.nombre ?? "Producto")
                        .font(.tituloGrande)
                        .foregroundStyle(Color.textoPrimario)
                        .lineLimit(2)
                    if let marca = producto?.marca, !marca.isEmpty {
                        Text(marca)
                            .font(.subtitulo)
                            .foregroundStyle(Color.textoSecundario)
                    }
                    if let categoria {
                        ChipCategoria(emoji: categoria.emoji, nombre: categoria.nombre)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: Espaciado.medio) {
                miniEstadistica(emoji: "📦", titulo: "Stock", valor: "\(stockTotal)")
                miniEstadistica(emoji: "🖼️", titulo: "Fotos", valor: "\(fotosTotales)")
                miniEstadistica(emoji: "🧾", titulo: "Movs.", valor: "\(movimientosProducto.count)")
            }
        }
        .tarjeta()
    }

    private func miniEstadistica(emoji: String, titulo: String, valor: String) -> some View {
        VStack(spacing: 2) {
            Text("\(emoji) \(valor)")
                .font(.subtitulo.weight(.bold))
                .foregroundStyle(Color.textoPrimario)
            Text(titulo)
                .font(.etiqueta)
                .foregroundStyle(Color.textoSecundario)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Espaciado.chico)
        .background(Color.superficieElevada, in: RoundedRectangle(cornerRadius: Radio.suave, style: .continuous))
    }

    // MARK: - Movimientos

    private var seccionMovimientos: some View {
        VStack(alignment: .leading, spacing: Espaciado.medio) {
            HStack {
                Text("🕰️ Línea de tiempo")
                    .font(.titulo)
                    .foregroundStyle(Color.textoPrimario)
                Spacer()
                if let ultimoMovimiento {
                    Button {
                        Inventario.deshacer(movimientoId: ultimoMovimiento.id, context: context)
                        Retroalimentacion.aviso()
                    } label: {
                        Text("↩️ Deshacer último")
                            .font(.etiqueta.weight(.semibold))
                            .foregroundStyle(Color.textoSobreAcento)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(Color.aviso, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            if movimientosProducto.isEmpty {
                VacioEstado(emoji: "🌙",
                            titulo: "Sin movimientos",
                            mensaje: "Todavía no entró ni salió nada de este producto.")
            } else {
                VStack(spacing: Espaciado.medio) {
                    ForEach(movimientosProducto, id: \.id) { movimiento in
                        VStack(alignment: .leading, spacing: Espaciado.chico) {
                            FilaMovimiento(fotoRuta: movimiento.fotoRuta,
                                           hora: hora(movimiento.fecha),
                                           usuario: movimiento.usuario,
                                           producto: nombreVariante(movimiento.varianteId),
                                           cantidad: movimiento.cantidad,
                                           tipo: movimiento.tipo,
                                           anulado: movimiento.anulado,
                                           motivoAnulacion: movimiento.motivoAnulacion,
                                           nota: movimiento.nota)

                            if !movimiento.anulado {
                                Button {
                                    motivoAnulacion = ""
                                    movimientoAAnular = movimiento
                                } label: {
                                    Text("🚫 Anular movimiento")
                                        .font(.etiqueta.weight(.semibold))
                                        .foregroundStyle(Color.peligro)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(Espaciado.medio)
                        .background(Color.superficie, in: RoundedRectangle(cornerRadius: Radio.medio, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radio.medio, style: .continuous).stroke(Color.borde, lineWidth: 1))
                    }
                }
            }
        }
    }

    // MARK: - Utilidades

    private func hora(_ fecha: Date) -> String {
        let formato = DateFormatter()
        formato.locale = Locale(identifier: "es_ES")
        formato.dateFormat = "d MMM · HH:mm"
        return formato.string(from: fecha)
    }

    private func nombreVariante(_ varianteId: UUID) -> String {
        guard let variante = variantes.first(where: { $0.id == varianteId }) else { return "Producto" }
        let nombre = producto?.nombre ?? "Producto"
        return "\(nombre) · \(Unidades.texto(variante.volumenML))"
    }

    private func movimientoDeFoto(_ ruta: String) -> Movimiento? {
        movimientos.first { $0.fotoRuta == ruta }
    }
}

// MARK: - Tarjeta de variante

/// Ficha de una variante: datos, stock, stock mínimo editable y fotos.
struct TarjetaVariante: View {
    @Bindable var variante: Variante
    var producto: Producto?
    var categoria: Categoria?
    var alVerFoto: (String) -> Void

    @Environment(\.modelContext) private var context

    private var stock: Int {
        Inventario.stock(varianteId: variante.id, context: context)
    }

    private var hayStockBajo: Bool {
        variante.stockMinimo > 0 && stock <= variante.stockMinimo
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Espaciado.medio) {
            HStack(spacing: Espaciado.medio) {
                Text(emojiDeCategoria(categoria: categoria, tipo: variante.tipo))
                    .font(.system(size: 28))
                VStack(alignment: .leading, spacing: 2) {
                    Text(Unidades.formateaLargo(variante.volumenML))
                        .font(.titulo)
                        .foregroundStyle(Color.textoPrimario)
                    if !variante.tipo.isEmpty {
                        Text(variante.tipo)
                            .font(.etiqueta)
                            .foregroundStyle(Color.textoSecundario)
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(hayStockBajo ? "⚠️ \(stock)" : "\(stock)")
                        .font(.cifra)
                        .foregroundStyle(hayStockBajo ? Color.aviso : Color.textoPrimario)
                    Text("en stock")
                        .font(.etiqueta)
                        .foregroundStyle(Color.textoSecundario)
                }
            }

            HStack(spacing: Espaciado.chico) {
                if !variante.sabor.isEmpty {
                    etiquetaDato("👅 \(variante.sabor)")
                }
                if variante.graduacion > 0 {
                    etiquetaDato("🌡️ \(graduacionTexto(variante.graduacion)) %")
                }
                if let codigo = variante.codigoBarras, !codigo.isEmpty {
                    etiquetaDato("🔑 \(codigo)")
                }
            }

            HStack(spacing: Espaciado.medio) {
                Text("📉 Mínimo")
                    .font(.etiqueta)
                    .foregroundStyle(Color.textoSecundario)

                Button {
                    variante.stockMinimo = max(0, variante.stockMinimo - 1)
                    try? context.save()
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.textoPrimario)
                        .frame(width: 44, height: 44)
                        .background(Color.superficieElevada, in: Circle())
                }
                .buttonStyle(.plain)

                Text("\(variante.stockMinimo)")
                    .font(.subtitulo.weight(.bold))
                    .foregroundStyle(Color.textoPrimario)
                    .frame(minWidth: 34)

                Button {
                    variante.stockMinimo = variante.stockMinimo + 1
                    try? context.save()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.textoPrimario)
                        .frame(width: 44, height: 44)
                        .background(Color.superficieElevada, in: Circle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Text("🖼️ \(variante.rutasFotos.count) fotos")
                    .font(.etiqueta)
                    .foregroundStyle(Color.textoSecundario)
            }

            if !variante.rutasFotos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Espaciado.chico) {
                        ForEach(variante.rutasFotos, id: \.self) { ruta in
                            Button {
                                alVerFoto(ruta)
                            } label: {
                                MiniaturaFoto(ruta: ruta, lado: 84)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .tarjeta()
    }

    private func etiquetaDato(_ texto: String) -> some View {
        Text(texto)
            .font(.etiqueta)
            .foregroundStyle(Color.textoSecundario)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.superficieElevada, in: Capsule())
    }

    /// Graduación con coma decimal (es-ES).
    private func graduacionTexto(_ valor: Double) -> String {
        let formato = NumberFormatter()
        formato.locale = Locale(identifier: "es_ES")
        formato.numberStyle = .decimal
        formato.minimumFractionDigits = 0
        formato.maximumFractionDigits = 1
        return formato.string(from: NSNumber(value: valor)) ?? "\(valor)"
    }
}

// MARK: - Identificador para la hoja de foto

/// Identificador simple para presentar la foto ampliada con `sheet(item:)`.
struct IdentificadorFoto: Identifiable, Hashable {
    let ruta: String
    var id: String { ruta }
}
