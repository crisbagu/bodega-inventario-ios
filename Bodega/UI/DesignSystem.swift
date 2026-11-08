import SwiftUI
import UIKit

// MARK: - Utilidad de color

/// Convierte un entero hexadecimal (0xRRGGBB) en UIColor.
func ui(_ hex: UInt32, alfa: CGFloat = 1) -> UIColor {
    UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alfa)
}

// MARK: - Paleta semántica (adaptativa, iOS 17)

/// Colores adaptativos: cambian solos entre modo claro y oscuro.
/// El color de acento es un vino sobrio (la app vive en una bodega, no en una oficina).
extension Color {

    /// Acento principal: vino profundo en claro, vino rosa en oscuro.
    static let acento = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? ui(0xE07A8C) : ui(0x8C2337)
    })

    /// Fondo general de la app (papel cálido / carbón cálido).
    static let fondo = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? ui(0x14100E) : ui(0xFAF6F3)
    })

    /// Tarjetas y superficies elevadas sobre el fondo.
    static let superficie = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? ui(0x211A17) : ui(0xFFFFFF)
    })

    /// Superficie un paso más elevada (chips, campos, cabeceras).
    static let superficieElevada = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? ui(0x2C2320) : ui(0xF3EAE5)
    })

    /// Bordes suaves de tarjetas y separadores.
    static let borde = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? ui(0x3A2E29) : ui(0xE6D9D2)
    })

    /// Texto principal (contraste alto).
    static let textoPrimario = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? ui(0xF5EDEA) : ui(0x1C1512)
    })

    /// Texto secundario (contraste medio, nunca por debajo de 4.5:1).
    static let textoSecundario = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? ui(0xC6B6AF) : ui(0x6B5A52)
    })

    /// Texto que va por encima del color de acento.
    static let textoSobreAcento = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? ui(0x14100E) : ui(0xFFFFFF)
    })

    /// Confirmaciones, stock sano.
    static let exito = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? ui(0x5FD69A) : ui(0x1E7A4C)
    })

    /// Avisos: stock bajo, Copia de seguridad vencida.
    static let aviso = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? ui(0xF5C24D) : ui(0x8A5A00)
    })

    /// Errores, anulaciones.
    static let peligro = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? ui(0xFF8A80) : ui(0xB3261E)
    })
}

// MARK: - Tipografía

/// Tipografía con curvas suaves ("rounded"), legible de lejos y con guantes.
extension Font {
    static let tituloGrande = Font.system(size: 32, weight: .bold, design: .rounded)
    static let titulo = Font.system(size: 24, weight: .bold, design: .rounded)
    static let subtitulo = Font.system(size: 19, weight: .semibold, design: .rounded)
    static let cuerpo = Font.system(size: 17, weight: .regular, design: .rounded)
    static let etiqueta = Font.system(size: 15, weight: .medium, design: .rounded)
    static let cifra = Font.system(size: 30, weight: .bold, design: .rounded)
}

// MARK: - Espaciado y radios

enum Espaciado {
    static let chico: CGFloat = 4
    static let medio: CGFloat = 12
    static let grande: CGFloat = 20
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

enum Radio {
    static let suave: CGFloat = 12
    static let medio: CGFloat = 16
    static let grande: CGFloat = 20
}

// MARK: - Constantes de interfaz

enum DesignSystem {
    /// Altura mínima de cualquier botón tocable.
    static let altoBoton: CGFloat = 60
    /// Altura de los botones principales de la pantalla de inicio.
    static let altoBotonHero: CGFloat = 96
    /// Lado de los botones circulares grandes (+/−).
    static let ladoBotonRedondo: CGFloat = 64
    /// Alto de las miniaturas de foto.
    static let ladoMiniatura: CGFloat = 72
    /// Umbral de confianza: por debajo hay que elegir a mano.
    static let umbralEleccion: Double = 0.60
    /// Umbral de confianza: por encima se puede aceptar de un toque.
    static let umbralAutomatico: Double = 0.90
}

// MARK: - Avisos entre pantallas

extension Notification.Name {
    /// Se avisa cuando cambia la unidad de visualización para que toda la app se refresque.
    static let bodegaUnidadCambiada = Notification.Name("bodega.unidad.cambiada")
}

// MARK: - Modificadores reutilizables

extension View {
    /// Estilo de tarjeta: superficie redondeada con borde apenas visible.
    func tarjeta(_ relleno: Color = .superficie) -> some View {
        self
            .padding(Espaciado.grande)
            .background(relleno, in: RoundedRectangle(cornerRadius: Radio.grande, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radio.grande, style: .continuous)
                    .stroke(Color.borde, lineWidth: 1)
            )
    }

    /// Título de sección con su emoji.
    func tituloSeccion(_ emoji: String, _ texto: String) -> some View {
        HStack(spacing: Espaciado.chico) {
            Text(emoji).font(.titulo)
            Text(texto).font(.titulo)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.textoPrimario)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
