import SwiftUI
import SwiftData

@main
struct BodegaApp: App {
    let container: ModelContainer

    init() {
        let esquema = Schema([Categoria.self, Producto.self, Variante.self, Movimiento.self, Usuario.self, Configuracion.self])
        do {
            container = try ModelContainer(for: esquema)
        } catch {
            // Si el almacenamiento falla (migración, disco lleno), seguimos en memoria.
            let memoria = ModelConfiguration(schema: esquema, isStoredInMemoryOnly: true)
            container = try! ModelContainer(for: esquema, configurations: [memoria])
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Color.acento)
        }
        .modelContainer(container)
    }
}
