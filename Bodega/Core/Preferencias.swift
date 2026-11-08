import Foundation

/// Preferencias locales de la app (viven en el teléfono, sin nube).
enum Preferencias {
    private static let prefijo = "bodega."

    /// Unidad en la que se muestran los volúmenes.
    static var unidadVisual: UnidadVisual {
        get {
            guard let valor = UserDefaults.standard.string(forKey: prefijo + "unidad") else { return .mililitros }
            return UnidadVisual(rawValue: valor) ?? .mililitros
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: prefijo + "unidad") }
    }

    /// Nombre de quien está operando ahora.
    static var usuarioActual: String {
        get { UserDefaults.standard.string(forKey: prefijo + "usuario") ?? "Operario" }
        set { UserDefaults.standard.set(newValue, forKey: prefijo + "usuario") }
    }

    /// Rol de quien está operando ahora.
    static var rolActual: RolUsuario {
        get {
            guard let valor = UserDefaults.standard.string(forKey: prefijo + "rol") else { return .operario }
            return RolUsuario(rawValue: valor) ?? .operario
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: prefijo + "rol") }
    }

    /// Última vez que se hizo la copia de seguridad.
    static var ultimaCopia: Date? {
        get { UserDefaults.standard.object(forKey: prefijo + "ultimaCopia") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: prefijo + "ultimaCopia") }
    }

    /// Días entre recordatorios de copia de seguridad.
    static var diasEntreCopias: Int {
        get {
            let valor = UserDefaults.standard.integer(forKey: prefijo + "diasCopia")
            return valor == 0 ? 7 : valor
        }
        set { UserDefaults.standard.set(max(1, newValue), forKey: prefijo + "diasCopia") }
    }

    /// Ya se hizo la copia de ejemplo (datos de prueba).
    static var datosSemillaCargados: Bool {
        get { UserDefaults.standard.bool(forKey: prefijo + "semilla") }
        set { UserDefaults.standard.set(newValue, forKey: prefijo + "semilla") }
    }

    /// Vibración al confirmar un movimiento.
    static var vibracionActiva: Bool {
        get {
            guard UserDefaults.standard.object(forKey: prefijo + "vibracion") != nil else { return true }
            return UserDefaults.standard.bool(forKey: prefijo + "vibracion")
        }
        set { UserDefaults.standard.set(newValue, forKey: prefijo + "vibracion") }
    }

    /// Sonido al confirmar un movimiento.
    static var sonidoActivo: Bool {
        get {
            guard UserDefaults.standard.object(forKey: prefijo + "sonido") != nil else { return true }
            return UserDefaults.standard.bool(forKey: prefijo + "sonido")
        }
        set { UserDefaults.standard.set(newValue, forKey: prefijo + "sonido") }
    }

    /// Tamaño máximo del lado mayor de la foto guardada (en píxeles).
    static var ladoMaximoFoto: Int {
        get {
            let valor = UserDefaults.standard.integer(forKey: prefijo + "ladoFoto")
            return valor == 0 ? 1600 : valor
        }
        set { UserDefaults.standard.set(max(600, newValue), forKey: prefijo + "ladoFoto") }
    }

    /// Borra todas las preferencias (reinicio de ajustes).
    static func borrarTodo() {
        for clave in UserDefaults.standard.dictionaryRepresentation().keys where clave.hasPrefix(prefijo) {
            UserDefaults.standard.removeObject(forKey: clave)
        }
    }
}
