import SwiftUI
import SwiftData

// MARK: - Usuarios

/// Alta, edición, cambio de rol, desactivación y borrado de usuarios.
struct UsuariosView: View {
    @Environment(\.modelContext) private var context

    @Query private var usuarios: [Usuario]

    @State private var aviso: AvisoUsuario? = nil
    @State private var nombre: String = ""
    @State private var usuarioAEditar: Usuario? = nil
    @State private var usuarioABorrar: Usuario? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Espaciado.grande) {
                    if usuarios.isEmpty {
                        VacioEstado(emoji: "👥",
                                    titulo: "No hay usuarios",
                                    mensaje: "Creá al primero para saber quién registra cada movimiento.")
                    } else {
                        VStack(spacing: Espaciado.chico) {
                            ForEach(usuarios, id: \.id) { usuario in
                                fila(usuario)
                            }
                        }
                        .tarjeta()
                    }

                    BotonGrande(titulo: "Crear usuario",
                                emoji: "➕",
                                estilo: .acento,
                                alto: 60) {
                        nombre = ""
                        aviso = .crear
                    }
                }
                .padding(Espaciado.grande)
            }
            .background(Color.fondo)
            .navigationTitle("Usuarios 👥")
            .navigationBarTitleDisplayMode(.inline)
            .alert(aviso?.titulo ?? "",
                   isPresented: Binding(get: { aviso != nil },
                                        set: { nuevo in if !nuevo { aviso = nil } }),
                   presenting: aviso) { aviso in
                switch aviso {
                case .editar:
                    TextField("Nombre", text: $nombre)
                    Button("Cancelar", role: .cancel) {}
                    Button("Guardar") { renombrar() }
                case .crear:
                    TextField("Nombre", text: $nombre)
                    Button("Cancelar", role: .cancel) {}
                    Button("Crear") { crear() }
                case .borrar:
                    Button("Cancelar", role: .cancel) {}
                    Button("Borrar", role: .destructive) { borrar() }
                }
            } message: { aviso in
                Text(aviso.mensaje)
            }
        }
    }

    // MARK: - Fila

    private func fila(_ usuario: Usuario) -> some View {
        let esActual = usuario.nombre == Preferencias.usuarioActual

        return HStack(spacing: Espaciado.medio) {
            PastillaEmoji(emoji: usuario.rol.emoji, lado: 44)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(usuario.nombre)
                        .font(.subtitulo)
                        .foregroundStyle(Color.textoPrimario)
                        .lineLimit(1)
                    if esActual {
                        Text("ACTUAL")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.acento.opacity(0.18), in: Capsule())
                            .foregroundStyle(Color.acento)
                    }
                }
                HStack(spacing: 6) {
                    Text(usuario.rol.titulo)
                        .font(.etiqueta)
                        .foregroundStyle(Color.textoSecundario)
                    if !usuario.activo {
                        Text("· Desactivado")
                            .font(.etiqueta)
                            .foregroundStyle(Color.peligro)
                    }
                }
            }

            Spacer(minLength: 0)

            Menu {
                Button {
                    usar(usuario)
                } label: {
                    Label("Operar como \(usuario.nombre)", systemImage: "person.crop.circle.badge.checkmark")
                }
                Button {
                    usuario.rol = (usuario.rol == .administrador) ? .operario : .administrador
                    try? context.save()
                    if esActual { Preferencias.rolActual = usuario.rol }
                    Retroalimentacion.exito()
                } label: {
                    Label("Cambiar rol", systemImage: "arrow.left.arrow.right")
                }
                Button {
                    nombre = usuario.nombre
                    usuarioAEditar = usuario
                    aviso = .editar
                } label: {
                    Label("Renombrar", systemImage: "pencil")
                }
                Button {
                    usuario.activo.toggle()
                    try? context.save()
                } label: {
                    Label(usuario.activo ? "Desactivar" : "Activar",
                          systemImage: usuario.activo ? "pause.circle" : "play.circle")
                }
                Button(role: .destructive) {
                    usuarioABorrar = usuario
                    aviso = .borrar
                } label: {
                    Label("Borrar", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.acento)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Opciones de \(usuario.nombre)")
        }
        .padding(.vertical, Espaciado.chico)
        .opacity(usuario.activo ? 1 : 0.6)
    }

    // MARK: - Acciones

    private func usar(_ usuario: Usuario) {
        Preferencias.usuarioActual = usuario.nombre
        Preferencias.rolActual = usuario.rol
        Retroalimentacion.exito()
    }

    private func renombrar() {
        guard let usuario = usuarioAEditar else { return }
        let limpio = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        if !limpio.isEmpty {
            if usuario.nombre == Preferencias.usuarioActual {
                Preferencias.usuarioActual = limpio
            }
            usuario.nombre = limpio
        }
        try? context.save()
        Retroalimentacion.exito()
    }

    private func crear() {
        let limpio = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty else { return }
        let nuevo = Usuario(nombre: limpio, rol: .operario, activo: true)
        context.insert(nuevo)
        try? context.save()
        Retroalimentacion.exito()
    }

    private func borrar() {
        guard let usuario = usuarioABorrar else { return }
        context.delete(usuario)
        try? context.save()
        Retroalimentacion.aviso()
    }
}

// MARK: - Avisos de usuarios

enum AvisoUsuario: Identifiable {
    case editar
    case crear
    case borrar

    var id: String {
        switch self {
        case .editar: return "editar"
        case .crear: return "crear"
        case .borrar: return "borrar"
        }
    }

    var titulo: String {
        switch self {
        case .editar: return "Renombrar usuario"
        case .crear: return "Nuevo usuario"
        case .borrar: return "¿Borrar el usuario?"
        }
    }

    var mensaje: String {
        switch self {
        case .editar: return "Escribí el nombre nuevo."
        case .crear: return "Escribí el nombre. Después podés cambiar el rol."
        case .borrar: return "Los movimientos ya registrados quedan con el nombre anterior."
        }
    }
}
