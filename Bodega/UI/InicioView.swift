import SwiftUI
import SwiftData
import UIKit

// MARK: - Inicio

/// Pantalla de inicio: los dos botones grandes (entrada y salida), el resumen de hoy,
/// las alertas de stock bajo y el acceso rápido.
struct InicioView: View {
    @Environment(\.modelContext) private var context

    @Query private var movimientos: [Movimiento]
    @Query private var variantes: [Variante]
    @Query private var productos: [Producto]
    @Query private var categorias: [Categoria]

    @State private var tipoActivo: TipoMovimiento? = nil
    @State private var mostrarCamara: Bool = false
    @State private var mostrarConfirmacion: Bool = false
    @State private var foto: UIImage? = nil
    @State private var mostrarUsuarios: Bool = false
    @State private var mostrarMovimientos: Bool = false
    @State private var busqueda: String = ""
    @State private var variantesBajas: [Variante] = []

    // MARK: - Datos de hoy

    private var movimientosHoy: [Movimiento] {
        movimientos.filter { Calendar.current.isDateInToday($0.fecha) && !$0.anulado }
    }

    private var entradasHoy: [Movimiento] {
        movimientosHoy.filter { $0.tipo == .entrada }
    }

    private var salidasHoy: [Movimiento] {
        movimientosHoy.filter { $0.tipo == .salida }
    }

    private var unidadesEntradas: Int {
        entradasHoy.reduce(0) { $0 + $1.cantidad }
    }

    private var unidadesSalidas: Int {
        salidasHoy.reduce(0) { $0 + $1.cantidad }
    }

    private var resultadosBusqueda: [Producto] {
        let texto = busqueda.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texto.isEmpty else { return [] }
        return productos
            .filter {
                $0.nombre.localizedCaseInsensitiveContains(texto)
                    || $0.marca.localizedCaseInsensitiveContains(texto)
            }
            .sorted { $0.nombre.localizedCaseInsensitiveCompare($1.nombre) == .orderedAscending }
    }

    // MARK: - Cuerpo

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Espaciado.grande) {
                    cabecera
                    botonesPrincipales
                    resumenHoy
                    seccionStockBajo
                    accesosRapidos
                    resultados
                }
                .padding(Espaciado.grande)
            }
            .background(Color.fondo)
            .navigationTitle("Bodega 🏷️")
            .navigationBarTitleDisplayMode(.large)
            .fullScreenCover(isPresented: $mostrarCamara) {
                CapturaFotoView(
                    alTomarFoto: { imagen in
                        foto = imagen
                        mostrarCamara = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            mostrarConfirmacion = true
                        }
                    },
                    alCancelar: { mostrarCamara = false }
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: $mostrarConfirmacion) {
                if let tipo = tipoActivo {
                    ConfirmacionView(tipo: tipo, imagen: foto)
                }
            }
            .sheet(isPresented: $mostrarUsuarios) {
                UsuariosView()
            }
            .sheet(isPresented: $mostrarMovimientos) {
                MovimientosView()
            }
            .task(id: movimientos.count) {
                refrescarAlertas()
            }
        }
    }

    // MARK: - Cabecera

    private var cabecera: some View {
        Button {
            mostrarUsuarios = true
        } label: {
            HStack(spacing: Espaciado.medio) {
                PastillaEmoji(emoji: Preferencias.rolActual.emoji, lado: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Operando: \(Preferencias.usuarioActual)")
                        .font(.subtitulo)
                        .foregroundStyle(Color.textoPrimario)
                        .lineLimit(1)
                    Text(Preferencias.rolActual.titulo)
                        .font(.etiqueta)
                        .foregroundStyle(Color.textoSecundario)
                }
                Spacer(minLength: 0)
                Text("Cambiar")
                    .font(.etiqueta.weight(.semibold))
                    .foregroundStyle(Color.acento)
            }
            .tarjeta()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Botones principales

    private var botonesPrincipales: some View {
        VStack(spacing: Espaciado.medio) {
            BotonGrande(titulo: "Entrada",
                        emoji: TipoMovimiento.entrada.emoji,
                        subtitulo: "Sumar botellas al stock",
                        estilo: .exito,
                        alto: DesignSystem.altoBotonHero) {
                abrirCamara(.entrada)
            }
            BotonGrande(titulo: "Salida",
                        emoji: TipoMovimiento.salida.emoji,
                        subtitulo: "Retirar botellas del stock",
                        estilo: .acento,
                        alto: DesignSystem.altoBotonHero) {
                abrirCamara(.salida)
            }
        }
    }

    private func abrirCamara(_ tipo: TipoMovimiento) {
        tipoActivo = tipo
        mostrarCamara = true
    }

    // MARK: - Resumen de hoy

    private var resumenHoy: some View {
        VStack(alignment: .leading, spacing: Espaciado.medio) {
            Text("📊 Hoy")
                .font(.titulo)
                .foregroundStyle(Color.textoPrimario)

            HStack(spacing: Espaciado.medio) {
                TarjetaResumen(emoji: "📥",
                               titulo: "Entradas",
                               valor: "\(unidadesEntradas)",
                               detalle: "\(entradasHoy.count) movimiento\(entradasHoy.count == 1 ? "" : "s")",
                               color: .exito)
                TarjetaResumen(emoji: "📤",
                               titulo: "Salidas",
                               valor: "\(unidadesSalidas)",
                               detalle: "\(salidasHoy.count) movimiento\(salidasHoy.count == 1 ? "" : "s")",
                               color: .aviso)
            }
        }
    }

    // MARK: - Stock bajo

    private var seccionStockBajo: some View {
        VStack(alignment: .leading, spacing: Espaciado.medio) {
            Text("⚠️ Stock bajo")
                .font(.titulo)
                .foregroundStyle(Color.textoPrimario)

            if variantesBajas.isEmpty {
                VacioEstado(emoji: "✅",
                            titulo: "Todo en orden",
                            mensaje: "No hay botellas por debajo del mínimo.")
            } else {
                VStack(spacing: Espaciado.chico) {
                    ForEach(variantesBajas, id: \.id) { variante in
                        NavigationLink {
                            DetalleProductoView(productoId: variante.productoId)
                        } label: {
                            filaStockBajo(variante)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .tarjeta()
            }
        }
    }

    private func filaStockBajo(_ variante: Variante) -> some View {
        let producto = productos.first { $0.id == variante.productoId }
        let stock = Inventario.stock(varianteId: variante.id, context: context)
        return HStack(spacing: Espaciado.medio) {
            PastillaEmoji(emoji: emojiDeCategoria(categoria: categoriaDe(producto), tipo: variante.tipo), lado: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(producto?.nombre ?? "Producto")
                    .font(.subtitulo)
                    .foregroundStyle(Color.textoPrimario)
                    .lineLimit(1)
                Text(Unidades.formateaLargo(variante.volumenML))
                    .font(.etiqueta)
                    .foregroundStyle(Color.textoSecundario)
            }
            Spacer(minLength: 0)
            Text("⚠️ \(stock)")
                .font(.subtitulo.weight(.bold))
                .foregroundStyle(Color.aviso)
            Image(systemName: "chevron.right")
                .font(.etiqueta.weight(.bold))
                .foregroundStyle(Color.textoSecundario)
        }
    }

    private func categoriaDe(_ producto: Producto?) -> Categoria? {
        guard let id = producto?.categoriaId else { return nil }
        return categorias.first { $0.id == id }
    }

    // MARK: - Accesos rápidos

    private var accesosRapidos: some View {
        VStack(spacing: Espaciado.chico) {
            BotonGrande(titulo: "Movimientos de hoy",
                        emoji: "🧾",
                        subtitulo: "\(movimientosHoy.count) registro\(movimientosHoy.count == 1 ? "" : "s")",
                        estilo: .neutro,
                        alto: 56) {
                mostrarMovimientos = true
            }
        }
    }

    // MARK: - Buscador

    private var resultados: some View {
        VStack(alignment: .leading, spacing: Espaciado.medio) {
            Text("🔍 Buscar producto")
                .font(.titulo)
                .foregroundStyle(Color.textoPrimario)

            TextField("Nombre o marca", text: $busqueda)
                .font(.cuerpo)
                .padding(.horizontal, Espaciado.grande)
                .frame(minHeight: DesignSystem.altoBoton)
                .background(Color.superficie, in: RoundedRectangle(cornerRadius: Radio.medio, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radio.medio, style: .continuous).stroke(Color.borde, lineWidth: 1))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !busqueda.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if resultadosBusqueda.isEmpty {
                    VacioEstado(emoji: "🔍", titulo: "Sin resultados", mensaje: "Probá con otro nombre.")
                } else {
                    VStack(spacing: Espaciado.chico) {
                        ForEach(resultadosBusqueda, id: \.id) { producto in
                            NavigationLink {
                                DetalleProductoView(productoId: producto.id)
                            } label: {
                                TarjetaProducto(producto: producto,
                                                emojiCategoria: emojiDeCategoria(categoria: categoriaDe(producto), tipo: producto.nombre),
                                                stock: stockTotal(producto),
                                                numeroFotos: fotosTotal(producto),
                                                rutaFoto: fotoPrincipal(producto))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Utilidades

    private func stockTotal(_ producto: Producto) -> Int {
        variantes
            .filter { $0.productoId == producto.id }
            .reduce(0) { $0 + Inventario.stock(varianteId: $1.id, context: context) }
    }

    private func fotosTotal(_ producto: Producto) -> Int {
        Set(variantes.filter { $0.productoId == producto.id }.flatMap { $0.rutasFotos }).count
    }

    private func fotoPrincipal(_ producto: Producto) -> String? {
        variantes
            .filter { $0.productoId == producto.id }
            .flatMap { $0.rutasFotos }
            .first
    }

    private func refrescarAlertas() {
        variantesBajas = Inventario.stockMinimoAlerta(context: context)
    }
}
