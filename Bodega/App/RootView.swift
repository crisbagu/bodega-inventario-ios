import SwiftUI
import SwiftData

struct RootView: View {
    var body: some View {
        TabView {
            InicioView()
                .tabItem { Label("Inicio", systemImage: "house.fill") }

            ListaProductosView()
                .tabItem { Label("Productos", systemImage: "shippingbox.fill") }

            GaleriaFotosView()
                .tabItem { Label("Fotos", systemImage: "photo.stack.fill") }

            ReportesView()
                .tabItem { Label("Reportes", systemImage: "chart.bar.xaxis") }

            AjustesView()
                .tabItem { Label("Ajustes", systemImage: "gearshape.fill") }
        }
    }
}
