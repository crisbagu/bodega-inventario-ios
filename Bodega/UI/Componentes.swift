import SwiftUI
import SwiftData

// MARK: - Utilidades de confianza

/// Normaliza la confianza a 0...1 sin importar si el motor la entrega como
/// fracción (0,92) o como porcentaje (92). Evita mostrar "9200 %".
func confianzaNormalizada(_ valor: Double) -> Double {
    if valor.isNaN { return 0 }
    if valor > 1 { return min(1, max(0, valor / 100)) }
    return min(1, max(0, valor))
}

// MARK: - Emoji de categoría

/// Emoji de una categoría: el de la categoría asignada y, si no hay, el que deduce el catálogo.
func emojiDeCategoria(categoria: Categoria?, tipo: String) -> String {
    if let categoria, !categoria.emoji.isEmpty { return categoria.emoji }
    let delCatalogo = Catalogo.emojiParaTipo(tipo)
    return delCatalogo.isEmpty ? "📦" : delCatalogo
}

// MARK: - Miniatura de foto

/// Miniatura cuadrada de una foto guardada en el almacén. Sin foto, muestra un marcador.
struct MiniaturaFoto: View {
    let ruta: String?
    var lado: CGFloat = DesignSystem.ladoMiniatura
    var radio: CGFloat = Radio.suave

    var body: some View {
        Group {
            if let ruta, let cg = AlmacenFotos.compartido.imagen(paraRuta: ruta) {
                Image(decorative: cg, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.superficieElevada
                    Image(systemName: "photo")
                        .font(.system(size: lado * 0.3))
                        .foregroundStyle(Color.textoSecundario)
                }
            }
        }
        .frame(width: lado, height: lado)
        .clipShape(RoundedRectangle(cornerRadius: radio, style: .continuous))
    }
}

// MARK: - Pastilla de emoji

/// Emoji dentro de un círculo, como punto de partida visual.
struct PastillaEmoji: View {
    let emoji: String
    var lado: CGFloat = 44

    var body: some View {
        Text(emoji)
            .font(.system(size: lado * 0.46))
            .frame(width: lado, height: lado)
            .background(Color.superficieElevada, in: Circle())
            .accessibilityHidden(true)
    }
}

// MARK: - Chip de categoría

/// Chip con emoji y nombre de categoría.
struct ChipCategoria: View {
    let emoji: String
    let nombre: String
    var color: Color = .acento

    var body: some View {
        HStack(spacing: 6) {
            Text(emoji).font(.system(size: 13))
            Text(nombre)
                .font(.etiqueta)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(color.opacity(0.14), in: Capsule())
        .foregroundStyle(color)
    }
}

// MARK: - Chip de confianza

/// Muestra el porcentaje de reconocimiento con color según el umbral:
/// verde ≥ 90 %, amarillo ≥ 60 %, rojo por debajo.
struct ChipConfianza: View {
    let confianza: Double

    private var valor: Double { confianzaNormalizada(confianza) }
    private var porcentaje: Int { Int((valor * 100).rounded()) }

    private var color: Color {
        if valor >= DesignSystem.umbralAutomatico { return .exito }
        if valor >= DesignSystem.umbralEleccion { return .aviso }
        return .peligro
    }

    private var icono: String {
        if valor >= DesignSystem.umbralAutomatico { return "checkmark.seal.fill" }
        if valor >= DesignSystem.umbralEleccion { return "exclamationmark.triangle.fill" }
        return "questionmark.circle.fill"
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icono)
                .font(.system(size: 12, weight: .bold))
            Text("\(porcentaje) %")
                .font(.etiqueta.weight(.bold))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(color.opacity(0.18), in: Capsule())
        .foregroundStyle(color)
    }
}

// MARK: - Barra de confianza

/// Barra de progreso del 0 al 100 % con el color del umbral.
struct BarraConfianza: View {
    let confianza: Double
    var alto: CGFloat = 12

    private var valor: Double { confianzaNormalizada(confianza) }
    private var color: Color {
        if valor >= DesignSystem.umbralAutomatico { return .exito }
        if valor >= DesignSystem.umbralEleccion { return .aviso }
        return .peligro
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.superficieElevada)
                Capsule()
                    .fill(color)
                    .frame(width: max(0, geo.size.width * valor))
            }
        }
        .frame(height: alto)
        .accessibilityLabel("Confianza \(Int((valor * 100).rounded())) por ciento")
    }
}

// MARK: - Tarjeta de resumen

/// Tarjeta con emoji, título, cifra grande y detalle opcional.
struct TarjetaResumen: View {
    let emoji: String
    let titulo: String
    let valor: String
    var detalle: String? = nil
    var color: Color = .acento

    var body: some View {
        VStack(alignment: .leading, spacing: Espaciado.chico) {
            HStack(spacing: 6) {
                Text(emoji).font(.system(size: 16))
                Text(titulo)
                    .font(.etiqueta)
                    .foregroundStyle(Color.textoSecundario)
            }
            Text(valor)
                .font(.cifra)
                .foregroundStyle(Color.textoPrimario)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let detalle {
                Text(detalle)
                    .font(.etiqueta)
                    .foregroundStyle(color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tarjeta()
    }
}

// MARK: - Botón grande

/// Botón principal de la app: alto, con emoji o icono, y subtítulo opcional.
struct BotonGrande: View {
    enum Estilo {
        case acento
        case neutro
        case peligro
        case exito
    }

    let titulo: String
    var emoji: String? = nil
    var icono: String? = nil
    var subtitulo: String? = nil
    var estilo: Estilo = .acento
    var alto: CGFloat = DesignSystem.altoBoton
    var habilitado: Bool = true
    let accion: () -> Void

    private var colorFondo: Color {
        switch estilo {
        case .acento: return .acento
        case .neutro: return .superficieElevada
        case .peligro: return .peligro
        case .exito: return .exito
        }
    }

    private var colorTexto: Color {
        switch estilo {
        case .acento, .peligro, .exito: return .textoSobreAcento
        case .neutro: return .textoPrimario
        }
    }

    var body: some View {
        Button(action: accion) {
            HStack(spacing: Espaciado.medio) {
                if let emoji {
                    Text(emoji).font(.system(size: 34))
                } else if let icono {
                    Image(systemName: icono).font(.system(size: 26, weight: .semibold))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(titulo)
                        .font(.titulo)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let subtitulo {
                        Text(subtitulo)
                            .font(.etiqueta)
                            .opacity(0.85)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(colorTexto)
            .padding(.horizontal, Espaciado.grande)
            .frame(maxWidth: .infinity, minHeight: alto)
            .background(colorFondo, in: RoundedRectangle(cornerRadius: Radio.grande, style: .continuous))
            .opacity(habilitado ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!habilitado)
        .accessibilityLabel(titulo)
    }
}

// MARK: - Etiqueta de volumen

/// Muestra el volumen en la unidad elegida por el usuario (ml o litros).
struct EtiquetaVolumen: View {
    let volumenML: Int
    /// Muestra las dos unidades: "750 ml · 0,75 L".
    var ambos: Bool = false
    var color: Color = .textoPrimario

    private var texto: String {
        ambos ? Unidades.formateaLargo(volumenML) : Unidades.formatea(volumenML, unidad: Preferencias.unidadVisual)
    }

    var body: some View {
        Text(texto)
            .font(.etiqueta.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.superficieElevada, in: Capsule())
    }
}

// MARK: - Fila de variante

/// Resumen de una variante: volumen, tipo, sabor, stock y número de fotos.
struct FilaVariante: View {
    let volumenML: Int
    let tipo: String
    let sabor: String
    let stock: Int
    var numeroFotos: Int = 0
    var stockMinimo: Int = 0
    var emoji: String = "🍶"

    private var hayStockBajo: Bool {
        stockMinimo > 0 && stock <= stockMinimo
    }

    var body: some View {
        HStack(spacing: Espaciado.medio) {
            PastillaEmoji(emoji: emoji, lado: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(Unidades.formateaLargo(volumenML))
                    .font(.subtitulo)
                    .foregroundStyle(Color.textoPrimario)
                if !tipo.isEmpty || !sabor.isEmpty {
                    Text([tipo, sabor].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.etiqueta)
                        .foregroundStyle(Color.textoSecundario)
                        .lineLimit(1)
                }
                HStack(spacing: 10) {
                    Text(hayStockBajo ? "⚠️ \(stock) en stock" : "\(stock) en stock")
                        .font(.etiqueta.weight(.semibold))
                        .foregroundStyle(hayStockBajo ? Color.aviso : Color.textoSecundario)
                    if numeroFotos > 0 {
                        Text("🖼️ \(numeroFotos)")
                            .font(.etiqueta)
                            .foregroundStyle(Color.textoSecundario)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Tarjeta de producto

/// Tarjeta de producto con miniatura de la foto, nombre, marca y stock.
struct TarjetaProducto: View {
    let nombre: String
    let marca: String
    var emojiCategoria: String = "📦"
    var stock: Int = 0
    var numeroFotos: Int = 0
    var rutaFoto: String? = nil
    var stockMinimo: Int = 0

    init(nombre: String,
         marca: String,
         emojiCategoria: String = "📦",
         stock: Int = 0,
         numeroFotos: Int = 0,
         rutaFoto: String? = nil,
         stockMinimo: Int = 0) {
        self.nombre = nombre
        self.marca = marca
        self.emojiCategoria = emojiCategoria
        self.stock = stock
        self.numeroFotos = numeroFotos
        self.rutaFoto = rutaFoto
        self.stockMinimo = stockMinimo
    }

    init(producto: Producto,
         emojiCategoria: String,
         stock: Int,
         numeroFotos: Int,
         rutaFoto: String? = nil,
         stockMinimo: Int = 0) {
        self.init(nombre: producto.nombre,
                  marca: producto.marca,
                  emojiCategoria: emojiCategoria,
                  stock: stock,
                  numeroFotos: numeroFotos,
                  rutaFoto: rutaFoto,
                  stockMinimo: stockMinimo)
    }

    private var hayStockBajo: Bool {
        stockMinimo > 0 && stock <= stockMinimo
    }

    var body: some View {
        HStack(spacing: Espaciado.medio) {
            ZStack(alignment: .bottomTrailing) {
                MiniaturaFoto(ruta: rutaFoto, lado: 72)
                Text(emojiCategoria)
                    .font(.system(size: 15))
                    .padding(5)
                    .background(Color.superficie, in: Circle())
                    .overlay(Circle().stroke(Color.borde, lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(nombre)
                    .font(.subtitulo)
                    .foregroundStyle(Color.textoPrimario)
                    .lineLimit(2)
                if !marca.isEmpty {
                    Text(marca)
                        .font(.etiqueta)
                        .foregroundStyle(Color.textoSecundario)
                        .lineLimit(1)
                }
                HStack(spacing: 10) {
                    Text(hayStockBajo ? "⚠️ \(stock) uds." : "📦 \(stock) uds.")
                        .font(.etiqueta.weight(.semibold))
                        .foregroundStyle(hayStockBajo ? Color.aviso : Color.textoSecundario)
                    if numeroFotos > 0 {
                        Text("🖼️ \(numeroFotos)")
                            .font(.etiqueta)
                            .foregroundStyle(Color.textoSecundario)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Estado vacío

/// Pantalla de estado vacío: emoji, texto y acción opcional.
struct VacioEstado: View {
    let emoji: String
    let titulo: String
    var mensaje: String? = nil
    var tituloAccion: String? = nil
    var accion: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Espaciado.medio) {
            Text(emoji).font(.system(size: 52))
            Text(titulo)
                .font(.subtitulo)
                .foregroundStyle(Color.textoPrimario)
                .multilineTextAlignment(.center)
            if let mensaje {
                Text(mensaje)
                    .font(.cuerpo)
                    .foregroundStyle(Color.textoSecundario)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Espaciado.grande)
            }
            if let tituloAccion, let accion {
                Button(action: accion) {
                    Text(tituloAccion)
                        .font(.subtitulo)
                        .foregroundStyle(Color.textoSobreAcento)
                        .padding(.horizontal, Espaciado.grande)
                        .frame(minHeight: DesignSystem.altoBoton)
                        .background(Color.acento, in: RoundedRectangle(cornerRadius: Radio.medio, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, Espaciado.chico)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Espaciado.xl)
    }
}

// MARK: - Fila de movimiento

/// Fila con foto, hora, usuario, producto y cantidad.
struct FilaMovimiento: View {
    let fotoRuta: String?
    let hora: String
    let usuario: String
    let producto: String
    let cantidad: Int
    let tipo: TipoMovimiento
    var anulado: Bool = false
    var motivoAnulacion: String = ""
    var nota: String = ""

    var body: some View {
        HStack(spacing: Espaciado.medio) {
            ZStack {
                MiniaturaFoto(ruta: fotoRuta, lado: 56)
                Text(tipo.emoji)
                    .font(.system(size: 13))
                    .padding(4)
                    .background(Color.superficie, in: Circle())
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(producto)
                    .font(.subtitulo)
                    .foregroundStyle(Color.textoPrimario)
                    .lineLimit(2)
                Text("\(hora) · \(usuario)")
                    .font(.etiqueta)
                    .foregroundStyle(Color.textoSecundario)
                if anulado {
                    Text("🚫 Anulado\(motivoAnulacion.isEmpty ? "" : ": \(motivoAnulacion)")")
                        .font(.etiqueta)
                        .foregroundStyle(Color.peligro)
                } else if !nota.isEmpty {
                    Text(nota)
                        .font(.etiqueta)
                        .foregroundStyle(Color.textoSecundario)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Text("\(tipo.emoji) \(cantidad)")
                .font(.subtitulo.weight(.bold))
                .foregroundStyle(anulado ? Color.textoSecundario : (tipo == .entrada ? Color.exito : Color.aviso))
                .strikethrough(anulado, color: Color.textoSecundario)
        }
        .opacity(anulado ? 0.65 : 1)
    }
}
