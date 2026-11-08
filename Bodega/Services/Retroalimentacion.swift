import Foundation
import UIKit
import AudioToolbox

/// Retroalimentación háptica y sonora al guardar un movimiento.
///
/// Este es el único archivo de `Services/` que importa UIKit (necesario para
/// los generadores de vibración). Respeta `Preferencias.vibracionActiva` y
/// `Preferencias.sonidoActivo`.
enum Retroalimentacion {

    /// Identificadores de sonido del sistema (AudioToolbox).
    /// 1104 = "Tink" breve, 1053 = "Tock", 1075 = alerta.
    private enum Sonido {
        static let exito: SystemSoundID = 1104
        static let error: SystemSoundID = 1053
        static let aviso: SystemSoundID = 1075
    }

    /// Confirmación: movimiento guardado.
    static func exito() {
        if Preferencias.vibracionActiva {
            let generador = UINotificationFeedbackGenerator()
            generador.prepare()
            generador.notificationOccurred(.success)
        }
        if Preferencias.sonidoActivo {
            AudioServicesPlaySystemSound(Sonido.exito)
        }
    }

    /// Error: no se pudo guardar o no hay stock.
    static func error() {
        if Preferencias.vibracionActiva {
            let generador = UINotificationFeedbackGenerator()
            generador.prepare()
            generador.notificationOccurred(.error)
        }
        if Preferencias.sonidoActivo {
            AudioServicesPlaySystemSound(Sonido.error)
        }
    }

    /// Aviso: algo pasó, pero no es un error (por ejemplo, movimiento duplicado).
    static func aviso() {
        if Preferencias.vibracionActiva {
            let generador = UINotificationFeedbackGenerator()
            generador.prepare()
            generador.notificationOccurred(.warning)
        }
        if Preferencias.sonidoActivo {
            AudioServicesPlaySystemSound(Sonido.aviso)
        }
    }
}
