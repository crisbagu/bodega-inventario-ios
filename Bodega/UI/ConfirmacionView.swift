import SwiftUI
import SwiftData
import UIKit

// MARK: - Pantalla de confirmación

/// Pantalla clave: muestra la foto, el texto reconocido, los candidatos y guarda el movimiento.
struct ConfirmacionView: View {

    let tipo: TipoMovimiento
    var imagen: UIImage? = nil
    var lectura: LecturaEtiqueta = LecturaEtiqueta()

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var cerrar

    @Query private var productos: [Producto]
    @Query private var categorias: [Categoria]
    @Query private var variantes: [Variante]

    @State private var textoOCR: String = ""
    @State private var lecturaActual: LecturaEtiqueta = LecturaEtiqueta()
    @State private var candidatos: [CandidatoVariante] = []
    @State private var colorHex: String? = nil
    @State private var seleccionado: CandidatoVariante? = nil
    @State private var cantidad: Int = 1
    @State private var cantidadTexto: String = "1"
    @State private var nota: String = ""
    @State private var mostrarTodos: Bool = false
    @State private var mostrarEditorManual: Bool = false
    @State private var textoManual: String = ""
    @State private var aviso: AvisoConfirmacion? = nil
    @State private var ignorarDuplicado: Bool = false
    @State private var rutaFoto: String? = nil
    @State private var analizando: Bool = true
    @State private var avisoUnidad: Int = 0

    init(tipo: TipoMovimiento, imagen: UIImage? = nil, lectura: LecturaEtiqueta = LecturaEtiqueta()) {
        self.tipo = tipo
        self.imagen = imagen
        self.lectura = lectura
        _textoOCR = State(initialValue: lectura.textoCompleto)
        _lecturaActual = State(initialValue: lectura)
    }

    // MARK: - Datos derivados

    private var mejorConfianza: Double {
        confianzaNormalizada(candidatos.first?.confianza ?? 0)
    }

    private var confianzaBaja: Bool {
        !candidatos.isEmpty && mejorConfianza < DesignSystem.umbralEleccion
    }

    /// Con confianza alta se muestran los tres mejores; con confianza baja, todos.
    private var candidatosVisibles: [CandidatoVariante] {
        if confianzaBaja || mostrarTodos { return candidatos }
        return Array(candidatos.prefix(3))
    }

    private var categoriaDe: Categoria? {
        guard let producto = productos.first(where: { $0.id == seleccionado?.productoId }) else { return nil }
        return categorias.first { $0.id == producto.categoriaId }
    }

    // MARK: - Cuerpo

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Espaciado.grande) {
                    seccionFoto
                    seccionTexto
                    seccionCandidatos
                    seccionCantidad
                    seccionNota
                    botonGuardar
                }
                .padding(Espaciado.grande)
            }
            .background(Color.fondo)
            .navigationTitle(tipo.titulo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { cerrar() }
                        .font(.subtitulo)
                }
            }
            .alert(
                aviso?.titulo ?? "",
                isPresented: Binding(get: { aviso != nil }, set: { nuevo in if !nuevo { aviso = nil } }),
                presenting: aviso
            ) { aviso in
                switch aviso {
                case .faltaCandidato:
                    Button("Entendido", role: .cancel) {}
                case .duplicado:
                    Button("Cancelar", role: .cancel) {}
                    Button("Registrar de nuevo", role: .destructive) {
                        ignorarDuplicado = true
                        guardar()
                    }
                case .stockNegativo:
                    Button("Cancelar", role: .cancel) {}
                    Button("Registrar igual", role: .destructive) {
                        guardar(forzarNegativo: true)
                    }
                case .error:
                    Button("Cerrar", role: .cancel) {}
                }
            } message: { aviso in
                Text(aviso.mensaje)
            }
            .sheet(isPresented: $mostrarEditorManual) {
                HojaTextoManual(texto: $textoManual) { nuevoTexto in
                    textoOCR = nuevoTexto
                    reaplicarTexto()
                }
            }
            .task { await analizar() }
            // Al editar el texto se vuelve a interpretar la etiqueta, pero esperando
            // un momento para no recalcular en cada tecla.
            .task(id: textoOCR) {
                do {
                    try await Task.sleep(nanoseconds: 700_000_000)
                } catch {
                    return
                }
                reaplicarTexto()
            }
            .onReceive(NotificationCenter.default.publisher(for: .bodegaUnidadCambiada)) { _ in
                avisoUnidad += 1
            }
        }
    }

    // MARK: - Sección foto

    private var seccionFoto: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let imagen {
                    Image(uiImage: imagen)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: Radio.grande, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: Radio.grande, style: .continuous)
                        .fill(Color.superficieElevada)
                        .frame(height: 140)
                        .overlay(Text("🖼️").font(.system(size: 48)))
                }
            }

            if !candidatos.isEmpty {
                ChipConfianza(confianza: mejorConfianza)
                    .padding(Espaciado.medio)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if analizando {
                HStack(spacing: 8) {
                    ProgressView().tint(.acento)
                    Text("Leyendo la etiqueta…").font(.etiqueta)
                }
                .foregroundStyle(Color.textoPrimario)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(Espaciado.medio)
            }
        }
    }

    // MARK: - Sección texto

    private var seccionTexto: some View {
        VStack(alignment: .leading, spacing: Espaciado.medio) {
            HStack {
                Text("🔤 Texto de la etiqueta")
                    .font(.subtitulo)
                    .foregroundStyle(Color.textoPrimario)
                Spacer()
                if !textoOCR.isEmpty {
                    Button {
                        UIPasteboard.general.string = textoOCR
                        Retroalimentacion.exito()
                    } label: {
                        Label("Copiar texto", systemImage: "doc.on.doc")
                            .font(.etiqueta.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.acento)
                }
            }

            TextEditor(text: $textoOCR)
                .font(.cuerpo)
                .frame(minHeight: 110)
                .scrollContentBackground(.hidden)
                .padding(Espaciado.chico)
                .background(Color.superficieElevada, in: RoundedRectangle(cornerRadius: Radio.medio, style: .continuous))

            HStack(spacing: Espaciado.medio) {
                Button {
                    textoManual = textoOCR
                    mostrarEditorManual = true
                } label: {
                    Label("✍️ Escribir a mano", systemImage: "square.and.pencil")
                        .font(.etiqueta.weight(.semibold))
                        .foregroundStyle(Color.textoPrimario)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 48)
                        .background(Color.superficieElevada, in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                if lecturaActual.volumenML != nil || lecturaActual.marca != nil {
                    VStack(alignment: .trailing, spacing: 2) {
                        if let volumen = lecturaActual.volumenML {
                            Text(Unidades.formateaLargo(volumen))
                                .font(.etiqueta.weight(.semibold))
                                .foregroundStyle(Color.textoPrimario)
                        }
                        if let marca = lecturaActual.marca {
                            Text(marca)
                                .font(.etiqueta)
                                .foregroundStyle(Color.textoSecundario)
                        }
                    }
                }
            }
        }
        .tarjeta()
    }

    // MARK: - Sección candidatos

    private var seccionCandidatos: some View {
        VStack(alignment: .leading, spacing: Espaciado.medio) {
            Text("🎯 ¿Qué producto es?")
                .font(.subtitulo)
                .foregroundStyle(Color.textoPrimario)

            if candidatos.isEmpty && !analizando {
                VacioEstado(emoji: "🔍",
                            titulo: "No encontré coincidencias",
                            mensaje: "Escribí el texto a mano o creá la variante nueva.")
            }

            if confianzaBaja {
                HStack(alignment: .top, spacing: Espaciado.medio) {
                    Text("⚠️").font(.system(size: 22))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Elegí o creá la variante")
                            .font(.subtitulo)
                            .foregroundStyle(Color.aviso)
                        Text("La lectura no es segura. Revisá las opciones de abajo.")
                            .font(.etiqueta)
                            .foregroundStyle(Color.textoSecundario)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Espaciado.medio)
                .background(Color.aviso.opacity(0.14), in: RoundedRectangle(cornerRadius: Radio.medio, style: .continuous))
            }

            ForEach(Array(candidatosVisibles.enumerated()), id: \.element.id) { indice, candidato in
                let destacado = indice == 0 && !confianzaBaja
                TarjetaCandidato(candidato: candidato,
                                 elegido: seleccionado?.varianteId == candidato.varianteId,
                                 destacado: destacado) {
                    seleccionado = candidato
                    Retroalimentacion.exito()
                }
            }

            if !confianzaBaja && candidatos.count > 3 {
                Button {
                    mostrarTodos.toggle()
                } label: {
                    Text(mostrarTodos ? "Ver sólo los mejores" : "Ver las \(candidatos.count) opciones")
                        .font(.etiqueta.weight(.semibold))
                        .foregroundStyle(Color.acento)
                }
                .buttonStyle(.plain)
            }

            BotonGrande(titulo: "Crear variante nueva",
                        emoji: "➕",
                        subtitulo: "Usá el texto que leímos",
                        estilo: .neutro,
                        alto: 56) {
                crearVarianteNueva()
            }
        }
        .tarjeta()
    }

    // MARK: - Sección cantidad

    private var seccionCantidad: some View {
        VStack(alignment: .leading, spacing: Espaciado.medio) {
            Text("🔢 Cantidad")
                .font(.subtitulo)
                .foregroundStyle(Color.textoPrimario)

            HStack(spacing: Espaciado.grande) {
                botonRedondo(icono: "minus") { ajustar(-1) }
                TextField("Cantidad", text: $cantidadTexto)
                    .font(.cifra)
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(Color.superficieElevada, in: RoundedRectangle(cornerRadius: Radio.medio, style: .continuous))
                    .onChange(of: cantidadTexto) { _, nuevo in
                        if let valor = Int(nuevo) { cantidad = max(1, valor) }
                    }
                botonRedondo(icono: "plus") { ajustar(1) }
            }
        }
        .tarjeta()
    }

    private func botonRedondo(icono: String, accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            Image(systemName: icono)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color.textoPrimario)
                .frame(width: DesignSystem.ladoBotonRedondo, height: DesignSystem.ladoBotonRedondo)
                .background(Color.superficieElevada, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(icono == "plus" ? "Sumar uno" : "Restar uno")
    }

    // MARK: - Sección nota

    private var seccionNota: some View {
        VStack(alignment: .leading, spacing: Espaciado.medio) {
            Text("📝 Nota (opcional)")
                .font(.subtitulo)
                .foregroundStyle(Color.textoPrimario)
            TextField("Algo que quieras recordar", text: $nota, axis: .vertical)
                .font(.cuerpo)
                .lineLimit(1...3)
                .padding(Espaciado.medio)
                .background(Color.superficieElevada, in: RoundedRectangle(cornerRadius: Radio.medio, style: .continuous))
        }
        .tarjeta()
    }

    // MARK: - Guardar

    private var botonGuardar: some View {
        BotonGrande(titulo: "Guardar \(tipo.titulo.lowercased())",
                    emoji: tipo.emoji,
                    subtitulo: seleccionado == nil ? "Elegí un producto" : "Cantidad: \(cantidad)",
                    estilo: .acento,
                    alto: 76) {
            guardar()
        }
        .disabled(seleccionado == nil)
    }

    // MARK: - Acciones

    private func ajustar(_ delta: Int) {
        let nuevo = max(1, cantidad + delta)
        cantidad = nuevo
        cantidadTexto = String(nuevo)
        Retroalimentacion.exito()
    }

    /// Analiza la foto (si hace falta) y calcula los candidatos.
    private func analizar() async {
        analizando = true
        var actual = lectura
        if actual.estaVacia, let cg = imagen?.cgImage {
            let ocr = await LectorOCR.leer(cg)
            var codigo = await LectorBarras.codigo(cg)
            if codigo == nil { codigo = ocr.codigoBarras }
            actual = LecturaEtiqueta(textoCompleto: ocr.textoCompleto,
                                     lineas: ocr.lineas,
                                     marca: ocr.marca,
                                     nombre: ocr.nombre,
                                     volumenML: ocr.volumenML,
                                     graduacion: ocr.graduacion,
                                     codigoBarras: codigo)
            colorHex = AnalizadorColor.dominante(cg)
        }
        lecturaActual = actual
        if textoOCR.isEmpty { textoOCR = actual.textoCompleto }
        let similitudes = await calcularSimilitudesVisuales()
        recalcularCandidatos(similitudes: similitudes)
        analizando = false
    }

    /// Compara la foto nueva con las fotos de referencia ya guardadas de cada variante
    /// (Vision FeaturePrint, dentro del teléfono). Solo para las 12 candidatas más
    /// probables: el trabajo pesado va fuera del hilo principal.
    private func calcularSimilitudesVisuales() async -> [UUID: Double] {
        guard let cg = imagen?.cgImage else { return [:] }
        let infos = Inventario.variantesInfo(context: context, productos: productos, categorias: categorias)
            .filter { !$0.rutasFotos.isEmpty }
            .prefix(12)
        guard !infos.isEmpty else { return [:] }
        let candidatas = Array(infos)
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var salida: [UUID: Double] = [:]
                for info in candidatas {
                    let mejor = MotorVisual.mejorSimilitud(contra: cg, referencias: info.rutasFotos) { ruta in
                        AlmacenFotos.compartido.imagen(paraRuta: ruta)
                    }
                    if mejor > 0 { salida[info.id] = mejor }
                }
                continuation.resume(returning: salida)
            }
        }
    }

    /// Vuelve a interpretar el texto editado y recalcula los candidatos.
    private func reaplicarTexto() {
        let nueva = LectorOCR.parsear(textoOCR)
        var resultado = nueva
        if resultado.codigoBarras == nil { resultado.codigoBarras = lecturaActual.codigoBarras }
        lecturaActual = resultado
        recalcularCandidatos()
    }

    private func recalcularCandidatos(similitudes: [UUID: Double] = [:]) {
        let infos = Inventario.variantesInfo(context: context, productos: productos, categorias: categorias)
        let nuevos = MotorCoincidencia.candidatos(lectura: lecturaActual,
                                                  colorHex: colorHex,
                                                  variantes: infos,
                                                  similitudesVisuales: similitudes)

        if let sel = seleccionado, !nuevos.contains(where: { $0.varianteId == sel.varianteId }) {
            seleccionado = nil
        }
        candidatos = nuevos

        if seleccionado == nil,
           let primero = nuevos.first,
           confianzaNormalizada(primero.confianza) >= DesignSystem.umbralAutomatico {
            seleccionado = primero
        }
    }

    private func guardarFoto() -> String? {
        if let rutaFoto { return rutaFoto }
        guard let cg = imagen?.cgImage else { return nil }
        if let ruta = try? AlmacenFotos.compartido.guardar(cg) {
            rutaFoto = ruta
            return ruta
        }
        return nil
    }

    /// Crea un producto y una variante nueva con lo que leímos de la etiqueta.
    private func crearVarianteNueva() {
        let nombre = (lecturaActual.nombre?.isEmpty == false)
            ? lecturaActual.nombre!
            : (textoOCR.isEmpty ? "Producto nuevo" : String(textoOCR.prefix(40)))
        let marca = (lecturaActual.marca?.isEmpty == false) ? lecturaActual.marca! : "Sin marca"
        let volumen = lecturaActual.volumenML ?? 750
        let categoria = categorias.first
        let pais = Catalogo.paisProbable(texto: textoOCR) ?? ""

        do {
            let variante = try Inventario.crearProducto(marca: marca,
                                                        nombre: nombre,
                                                        pais: pais,
                                                        esImportado: pais.isEmpty ? false : Catalogo.esImportado(pais: pais),
                                                        categoriaId: categoria?.id,
                                                        volumenML: volumen,
                                                        tipo: lecturaActual.nombre ?? "",
                                                        sabor: "",
                                                        graduacion: lecturaActual.graduacion ?? 0,
                                                        codigoBarras: lecturaActual.codigoBarras,
                                                        context: context)

            let ruta = guardarFoto()
            if let ruta { variante.rutasFotos = [ruta] }
            try? context.save()

            let candidato = CandidatoVariante(varianteId: variante.id,
                                              productoId: variante.productoId,
                                              nombreProducto: nombre,
                                              marca: marca,
                                              categoria: categoria?.nombre ?? "",
                                              volumenML: variante.volumenML,
                                              tipo: variante.tipo,
                                              sabor: variante.sabor,
                                              graduacion: variante.graduacion,
                                              confianza: 1,
                                              fotoRuta: ruta,
                                              esNuevo: true)
            seleccionado = candidato
            candidatos = [candidato] + candidatos
            Retroalimentacion.exito()
        } catch {
            aviso = .error(error.localizedDescription)
            Retroalimentacion.error()
        }
    }

    private func guardar(forzarNegativo: Bool = false) {
        guard let sel = seleccionado else {
            aviso = .faltaCandidato
            return
        }
        guard cantidad > 0 else {
            aviso = .faltaCandidato
            return
        }

        if !ignorarDuplicado,
           Inventario.detectarDuplicado(varianteId: sel.varianteId,
                                        tipo: tipo,
                                        cantidad: cantidad,
                                        context: context) != nil {
            aviso = .duplicado
            return
        }

        if tipo == .salida && !forzarNegativo {
            let stockActual = Inventario.stock(varianteId: sel.varianteId, context: context)
            if stockActual - cantidad < 0 {
                aviso = .stockNegativo
                return
            }
        }

        registrar(sel)
    }

    private func registrar(_ sel: CandidatoVariante) {
        let ruta = guardarFoto()
        do {
            _ = try Inventario.guardarMovimiento(varianteId: sel.varianteId,
                                                  tipo: tipo,
                                                  cantidad: cantidad,
                                                  fotoRuta: ruta,
                                                  nota: nota,
                                                  confianza: confianzaNormalizada(sel.confianza),
                                                  usuario: Preferencias.usuarioActual,
                                                  textoOCR: lecturaActual.textoCompleto,
                                                  codigoBarras: lecturaActual.codigoBarras,
                                                  context: context)
            // La foto también queda en la variante para verla en la galería.
            if let ruta, let variante = variantes.first(where: { $0.id == sel.varianteId }) {
                if !variante.rutasFotos.contains(ruta) {
                    variante.rutasFotos.append(ruta)
                }
                try? context.save()
            }
            Retroalimentacion.exito()
            cerrar()
        } catch {
            aviso = .error(error.localizedDescription)
            Retroalimentacion.error()
        }
    }
}

// MARK: - Tarjeta de candidato

/// Fila de candidato con su porcentaje de confianza.
struct TarjetaCandidato: View {
    let candidato: CandidatoVariante
    let elegido: Bool
    let destacado: Bool
    let accion: () -> Void

    private var emoji: String {
        emojiDeCategoria(categoria: nil, tipo: candidato.tipo)
    }

    var body: some View {
        Button(action: accion) {
            VStack(alignment: .leading, spacing: Espaciado.chico) {
                HStack(spacing: Espaciado.medio) {
                    Text(emoji).font(.system(size: 26))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(candidato.nombreProducto)
                            .font(destacado ? .subtitulo : .cuerpo.weight(.semibold))
                            .foregroundStyle(Color.textoPrimario)
                            .lineLimit(1)
                        Text(candidato.marca)
                            .font(.etiqueta)
                            .foregroundStyle(Color.textoSecundario)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    ChipConfianza(confianza: candidato.confianza)
                }

                HStack(spacing: 8) {
                    EtiquetaVolumen(volumenML: candidato.volumenML)
                    if !candidato.tipo.isEmpty {
                        Text(candidato.tipo)
                            .font(.etiqueta)
                            .foregroundStyle(Color.textoSecundario)
                    }
                    if !candidato.sabor.isEmpty {
                        Text("· \(candidato.sabor)")
                            .font(.etiqueta)
                            .foregroundStyle(Color.textoSecundario)
                    }
                    Spacer(minLength: 0)
                }

                if destacado {
                    BarraConfianza(confianza: candidato.confianza)
                }

                if !candidato.detalleCoincidencias.isEmpty {
                    Text(candidato.detalleCoincidencias.joined(separator: " · "))
                        .font(.etiqueta)
                        .foregroundStyle(Color.textoSecundario)
                        .lineLimit(2)
                }
            }
            .padding(Espaciado.medio)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(elegido ? Color.acento.opacity(0.14) : Color.superficieElevada,
                        in: RoundedRectangle(cornerRadius: Radio.medio, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radio.medio, style: .continuous)
                    .stroke(elegido ? Color.acento : Color.borde, lineWidth: elegido ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Hoja de escritura manual

/// Hoja para escribir el texto de la etiqueta a mano.
struct HojaTextoManual: View {
    @Binding var texto: String
    var alAplicar: (String) -> Void
    @Environment(\.dismiss) private var cerrar

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Espaciado.medio) {
                Text("✍️ Escribí lo que dice la etiqueta")
                    .font(.subtitulo)
                    .foregroundStyle(Color.textoSecundario)

                TextEditor(text: $texto)
                    .font(.cuerpo)
                    .frame(minHeight: 220)
                    .scrollContentBackground(.hidden)
                    .padding(Espaciado.chico)
                    .background(Color.superficieElevada, in: RoundedRectangle(cornerRadius: Radio.medio, style: .continuous))

                Spacer()

                BotonGrande(titulo: "Buscar coincidencias",
                            emoji: "🔍",
                            alto: 64) {
                    alAplicar(texto)
                    cerrar()
                }
            }
            .padding(Espaciado.grande)
            .background(Color.fondo)
            .navigationTitle("Texto a mano")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { cerrar() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Avisos

enum AvisoConfirmacion: Identifiable {
    case faltaCandidato
    case duplicado
    case stockNegativo
    case error(String)

    var id: String {
        switch self {
        case .faltaCandidato: return "falta"
        case .duplicado: return "duplicado"
        case .stockNegativo: return "stock"
        case .error(let mensaje): return "error-\(mensaje)"
        }
    }

    var titulo: String {
        switch self {
        case .faltaCandidato: return "Elegí un producto"
        case .duplicado: return "¿Registrar de nuevo?"
        case .stockNegativo: return "No hay stock suficiente"
        case .error: return "No se pudo guardar"
        }
    }

    var mensaje: String {
        switch self {
        case .faltaCandidato:
            return "Tocá uno de los candidatos o creá una variante nueva."
        case .duplicado:
            return "Acabás de registrar un movimiento igual hace un momento. ¿Querés guardarlo igual?"
        case .stockNegativo:
            return "Esta salida dejaría el stock en negativo. Revisá la cantidad o registrala igual si sabés lo que hacés."
        case .error(let mensaje):
            return mensaje
        }
    }
}
