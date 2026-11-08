import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Ajustes

/// Ajustes: unidades, usuario, categorías, copias de seguridad, exportación, espacio y avisos.
struct AjustesView: View {
    @Environment(\.modelContext) private var context

    @Query private var movimientos: [Movimiento]
    @Query private var variantes: [Variante]
    @Query private var productos: [Producto]
    @Query private var usuarios: [Usuario]

    @State private var mostrarImportar: Bool = false
    @State private var urlExport: URL? = nil
    @State private var aviso: AvisoAjustes? = nil
    @State private var confirmacionBorrarDemo: Bool = false

    private var esAdmin: Bool { Preferencias.rolActual == .administrador }

    // MARK: - Datos

    private var totalFotos: Int {
        Set(variantes.flatMap { $0.rutasFotos }).count
    }

    private var espacioLegible: String {
        let bytes = AlmacenFotos.compartido.espacioUsado()
        let formato = ByteCountFormatter()
        formato.countStyle = .file
        return formato.string(fromByteCount: max(0, bytes))
    }

    private var diasDesdeCopia: Int? {
        guard let ultima = Preferencias.ultimaCopia else { return nil }
        let dias = Calendar.current.dateComponents([.day], from: ultima, to: Date()).day ?? 0
        return max(0, dias)
    }

    private var copiaVencida: Bool {
        guard let dias = diasDesdeCopia else { return true }
        return dias >= Preferencias.diasEntreCopias
    }

    // MARK: - Cuerpo

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Espaciado.grande) {
                    seccionUnidad
                    seccionUsuario
                    if esAdmin {
                        seccionCategorias
                    }
                    seccionCopia
                    seccionExportar
                    seccionEspacio
                    if esAdmin {
                        seccionDemo
                    }
                    seccionFeedback
                    seccionRoles
                }
                .padding(Espaciado.grande)
            }
            .background(Color.fondo)
            .navigationTitle("Ajustes ⚙️")
            .navigationBarTitleDisplayMode(.large)
            .fileImporter(isPresented: $mostrarImportar,
                          allowedContentTypes: [.zip],
                          allowsMultipleSelection: false) { resultado in
                switch resultado {
                case .success(let urls):
                    restaurar(desde: urls.first)
                case .failure(let error):
                    aviso = .error(error.localizedDescription)
                }
            }
            .alert(aviso?.titulo ?? "",
                   isPresented: Binding(get: { aviso != nil },
                                        set: { nuevo in if !nuevo { aviso = nil } }),
                   presenting: aviso) { _ in
                Button("Entendido", role: .cancel) {}
            } message: { detalle in
                Text(detalle.mensaje)
            }
            .confirmationDialog("¿Borrar los datos de ejemplo?",
                                isPresented: $confirmacionBorrarDemo,
                                titleVisibility: .visible) {
                Button("🗑️ Borrar datos de ejemplo", role: .destructive) {
                    DatosSemilla.borrarTodo(context: context)
                    aviso = .info("Se borraron los datos de ejemplo.")
                    Retroalimentacion.aviso()
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Solo se borran los productos de prueba. Tus datos quedan intactos.")
            }
        }
    }

    // MARK: - Sección unidad

    private var seccionUnidad: some View {
        VStack(alignment: .leading, spacing: Espaciado.medio) {
            Text("🥛 Unidad de las medidas")
                .font(.titulo)
                .foregroundStyle(Color.textoPrimario)

            Picker("Unidad", selection: Binding(
                get: { Preferencias.unidadVisual },
                set: {
                    Preferencias.unidadVisual = $0
                    NotificationCenter.default.post(name: .bodegaUnidadCambiada, object: nil)
                }
            )) {
                ForEach(UnidadVisual.allCases) { unidad in
                    Text("\(unidad.emoji) \(unidad.titulo)").tag(unidad)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: Preferencias.unidadVisual) { _, _ in
                Retroalimentacion.exito()
            }

            Text("Ejemplo: 750 ml se muestra como \(Unidades.formatea(750, unidad: Preferencias.unidadVisual)).")
                .font(.etiqueta)
                .foregroundStyle(Color.textoSecundario)
        }
        .tarjeta()
    }

    // MARK: - Sección usuario

    private var seccionUsuario: some View {
        VStack(alignment: .leading, spacing: Espaciado.medio) {
            Text("👤 Quién opera")
                .font(.titulo)
                .foregroundStyle(Color.textoPrimario)

            HStack(spacing: Espaciado.medio) {
                PastillaEmoji(emoji: Preferencias.rolActual.emoji, lado: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Preferencias.usuarioActual)
                        .font(.subtitulo)
                        .foregroundStyle(Color.textoPrimario)
                    Text(Preferencias.rolActual.titulo)
                        .font(.etiqueta)
                        .foregroundStyle(Color.textoSecundario)
                }
                Spacer(minLength: 0)
            }

            NavigationLink {
                UsuariosView()
            } label: {
                HStack {
                    Text("🛠️ Gestionar usuarios")
                        .font(.subtitulo)
                        .foregroundStyle(Color.acento)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color.acento)
                }
                .padding(.vertical, Espaciado.chico)
            }
            .buttonStyle(.plain)
        }
        .tarjeta()
    }

    // MARK: - Sección categorías

    private var seccionCategorias: some View {
        VStack(alignment: .leading, spacing: Espaciado.medio) {
            Text("🗂️ Categorías")
                .font(.titulo)
                .foregroundStyle(Color.textoPrimario)

            NavigationLink {
                CategoriasView()
            } label: {
                HStack {
                    Text("🏷️ Ordenar y renombrar categorías")
                        .font(.subtitulo)
                        .foregroundStyle(Color.acento)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color.acento)
                }
                .padding(.vertical, Espaciado.chico)
            }
            .buttonStyle(.plain)
        }
        .tarjeta()
    }

    // MARK: - Sección copia de seguridad

    private var seccionCopia: some View {
        VStack(alignment: .leading, spacing: Espaciado.medio) {
            Text("🛡️ Copia de seguridad")
                .font(.titulo)
                .foregroundStyle(Color.textoPrimario)

            if copiaVencida {
                HStack(alignment: .top, spacing: Espaciado.medio) {
                    Text("⚠️").font(.system(size: 20))
                    Text(diasDesdeCopia == nil
                         ? "Todavía no hiciste ninguna copia."
                         : "La última copia tiene \(diasDesdeCopia ?? 0) día\(diasDesdeCopia == 1 ? "" : "s").")
                        .font(.etiqueta)
                        .foregroundStyle(Color.aviso)
                    Spacer(minLength: 0)
                }
                .padding(Espaciado.medio)
                .background(Color.aviso.opacity(0.14), in: RoundedRectangle(cornerRadius: Radio.medio, style: .continuous))
            }

            BotonGrande(titulo: "Exportar copia",
                        emoji: "📤",
                        subtitulo: "Guarda todo en un archivo .zip",
                        estilo: .acento,
                        alto: 60) {
                exportarCopia()
            }

            BotonGrande(titulo: "Restaurar copia",
                        emoji: "📥",
                        subtitulo: "Recupera desde un archivo .zip",
                        estilo: .neutro,
                        alto: 60) {
                mostrarImportar = true
            }

            HStack {
                Text("Última copia")
                    .font(.etiqueta)
                    .foregroundStyle(Color.textoSecundario)
                Spacer()
                Text(textoUltimaCopia)
                    .font(.etiqueta.weight(.semibold))
                    .foregroundStyle(Color.textoPrimario)
            }

            Stepper(value: Binding(
                get: { Preferencias.diasEntreCopias },
                set: { Preferencias.diasEntreCopias = $0 }
            ), in: 1...60) {
                HStack {
                    Text("🔔 Avisar cada")
                        .font(.etiqueta)
                        .foregroundStyle(Color.textoSecundario)
                    Spacer()
                    Text("\(Preferencias.diasEntreCopias) día\(Preferencias.diasEntreCopias == 1 ? "" : "s")")
                        .font(.etiqueta.weight(.semibold))
                        .foregroundStyle(Color.textoPrimario)
                }
            }
        }
        .tarjeta()
    }

    private var textoUltimaCopia: String {
        guard let ultima = Preferencias.ultimaCopia else { return "Nunca" }
        let formato = DateFormatter()
        formato.locale = Locale(identifier: "es_ES")
        formato.dateFormat = "d MMM yyyy · HH:mm"
        return formato.string(from: ultima)
    }

    // MARK: - Sección exportar

    private var seccionExportar: some View {
        VStack(alignment: .leading, spacing: Espaciado.medio) {
            Text("📊 Exportar datos")
                .font(.titulo)
                .foregroundStyle(Color.textoPrimario)

            HStack(spacing: Espaciado.chico) {
                BotonGrande(titulo: "CSV",
                            emoji: "📄",
                            subtitulo: "Movimientos",
                            estilo: .neutro,
                            alto: 56) {
                    exportarMovimientos(formato: .csv)
                }
                BotonGrande(titulo: "Excel",
                            emoji: "📊",
                            subtitulo: "Movimientos",
                            estilo: .neutro,
                            alto: 56) {
                    exportarMovimientos(formato: .excel)
                }
            }

            HStack(spacing: Espaciado.chico) {
                BotonGrande(titulo: "CSV",
                            emoji: "📄",
                            subtitulo: "Variantes",
                            estilo: .neutro,
                            alto: 56) {
                    exportarVariantes(formato: .csv)
                }
                BotonGrande(titulo: "Excel",
                            emoji: "📊",
                            subtitulo: "Variantes",
                            estilo: .neutro,
                            alto: 56) {
                    exportarVariantes(formato: .excel)
                }
            }

            if let urlExport {
                ShareLink(item: urlExport) {
                    HStack(spacing: Espaciado.medio) {
                        Text("📨").font(.system(size: 22))
                        Text("Compartir \(urlExport.lastPathComponent)")
                            .font(.etiqueta.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Color.textoSobreAcento)
                    .padding(.horizontal, Espaciado.grande)
                    .frame(maxWidth: .infinity, minHeight: DesignSystem.altoBoton)
                    .background(Color.acento, in: RoundedRectangle(cornerRadius: Radio.medio, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .tarjeta()
    }

    // MARK: - Espacio usado

    private var seccionEspacio: some View {
        VStack(alignment: .leading, spacing: Espaciado.medio) {
            Text("💽 Espacio usado")
                .font(.titulo)
                .foregroundStyle(Color.textoPrimario)

            HStack(spacing: Espaciado.medio) {
                miniDato(emoji: "🖼️", titulo: "Fotos", valor: "\(totalFotos)")
                miniDato(emoji: "📦", titulo: "Peso", valor: espacioLegible)
                miniDato(emoji: "🫙", titulo: "Variantes", valor: "\(variantes.count)")
            }
        }
        .tarjeta()
    }

    private func miniDato(emoji: String, titulo: String, valor: String) -> some View {
        VStack(spacing: 2) {
            Text("\(emoji) \(valor)")
                .font(.subtitulo.weight(.bold))
                .foregroundStyle(Color.textoPrimario)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(titulo)
                .font(.etiqueta)
                .foregroundStyle(Color.textoSecundario)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Espaciado.chico)
        .background(Color.superficieElevada, in: RoundedRectangle(cornerRadius: Radio.suave, style: .continuous))
    }

    // MARK: - Datos de ejemplo

    private var seccionDemo: some View {
        VStack(alignment: .leading, spacing: Espaciado.medio) {
            Text("🧪 Datos de ejemplo")
                .font(.titulo)
                .foregroundStyle(Color.textoPrimario)

            Text("Sirven para probar la app sin cargar nada real.")
                .font(.etiqueta)
                .foregroundStyle(Color.textoSecundario)

            BotonGrande(titulo: "Cargar datos de ejemplo",
                        emoji: "🌱",
                        estilo: .neutro,
                        alto: 56) {
                DatosSemilla.cargarSiHaceFalta(context: context)
                aviso = .info("Datos de ejemplo cargados.")
                Retroalimentacion.exito()
            }

            BotonGrande(titulo: "Borrar datos de ejemplo",
                        emoji: "🗑️",
                        estilo: .peligro,
                        alto: 56) {
                confirmacionBorrarDemo = true
            }
        }
        .tarjeta()
    }

    // MARK: - Feedback

    private var seccionFeedback: some View {
        VStack(alignment: .leading, spacing: Espaciado.medio) {
            Text("📳 Vibación y sonido")
                .font(.titulo)
                .foregroundStyle(Color.textoPrimario)

            Toggle(isOn: Binding(
                get: { Preferencias.vibracionActiva },
                set: { Preferencias.vibracionActiva = $0 }
            )) {
                Text("📳 Vibrar al guardar")
                    .font(.cuerpo)
                    .foregroundStyle(Color.textoPrimario)
            }
            .tint(Color.acento)

            Toggle(isOn: Binding(
                get: { Preferencias.sonidoActivo },
                set: { Preferencias.sonidoActivo = $0 }
            )) {
                Text("🔔 Sonido al guardar")
                    .font(.cuerpo)
                    .foregroundStyle(Color.textoPrimario)
            }
            .tint(Color.acento)
        }
        .tarjeta()
    }

    // MARK: - Roles

    private var seccionRoles: some View {
        VStack(alignment: .leading, spacing: Espaciado.medio) {
            Text("🧑‍🔧 Modo de trabajo")
                .font(.titulo)
                .foregroundStyle(Color.textoPrimario)

            Picker("Rol", selection: Binding(
                get: { Preferencias.rolActual },
                set: { Preferencias.rolActual = $0 }
            )) {
                ForEach(RolUsuario.allCases) { rol in
                    Text("\(rol.emoji) \(rol.titulo)").tag(rol)
                }
            }
            .pickerStyle(.segmented)

            Text(esAdmin
                 ? "Como administrador podés editar productos, categorías y datos de ejemplo."
                 : "Como operario ves la app simple: sólo registrar entradas y salidas.")
                .font(.etiqueta)
                .foregroundStyle(Color.textoSecundario)
        }
        .tarjeta()
    }

    // MARK: - Acciones

    private func exportarCopia() {
        do {
            let url = try Respaldo.exportarTodo(context: context)
            Preferencias.ultimaCopia = Date()
            aviso = .info("Copia guardada en \(url.lastPathComponent).")
            Retroalimentacion.exito()
        } catch {
            aviso = .error(error.localizedDescription)
            Retroalimentacion.error()
        }
    }

    private func restaurar(desde url: URL?) {
        guard let url else { return }
        let acceso = url.startAccessingSecurityScopedResource()
        defer { if acceso { url.stopAccessingSecurityScopedResource() } }
        do {
            try Respaldo.importar(desde: url, context: context)
            aviso = .info("Copia restaurada.")
            Retroalimentacion.exito()
        } catch {
            aviso = .error(error.localizedDescription)
            Retroalimentacion.error()
        }
    }

    private func exportarMovimientos(formato: FormatoExport) {
        let filas = Exportador.filasMovimientos(movimientos: movimientos,
                                                variantes: variantes,
                                                productos: productos,
                                                unidad: Preferencias.unidadVisual)
        guard !filas.isEmpty else {
            aviso = .info("Todavía no hay movimientos para exportar.")
            return
        }
        urlExport = formato == .csv
            ? Exportador.csv(filas: filas)
            : Exportador.excel(filas: filas, titulo: "Movimientos")
        Retroalimentacion.exito()
    }

    private func exportarVariantes(formato: FormatoExport) {
        let filas = Exportador.filasVariantes(variantes: variantes,
                                               productos: productos,
                                               unidad: Preferencias.unidadVisual)
        guard !filas.isEmpty else {
            aviso = .info("Todavía no hay variantes para exportar.")
            return
        }
        urlExport = formato == .csv
            ? Exportador.csv(filas: filas)
            : Exportador.excel(filas: filas, titulo: "Variantes")
        Retroalimentacion.exito()
    }
}

// MARK: - Formato de exportación

enum FormatoExport {
    case csv
    case excel
}

// MARK: - Avisos de ajustes

/// Mensaje mostrado al usuario desde Ajustes.
enum AvisoAjustes: Identifiable {
    case info(String)
    case error(String)

    var id: String {
        switch self {
        case .info(let texto): return "info-\(texto)"
        case .error(let texto): return "error-\(texto)"
        }
    }

    var titulo: String {
        switch self {
        case .info: return "Bodega"
        case .error: return "No se pudo completar"
        }
    }

    var mensaje: String {
        switch self {
        case .info(let texto): return texto
        case .error(let texto): return texto
        }
    }
}
