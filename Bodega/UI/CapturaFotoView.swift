import SwiftUI
import UIKit
import AVFoundation
import PhotosUI

// MARK: - Selector de cámara

/// Envoltorio de `UIImagePickerController` (cámara). Devuelve la imagen y permite cancelar.
struct SelectorCamara: UIViewControllerRepresentable {
    var alTomarFoto: (UIImage) -> Void
    var alCancelar: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .savedPhotosAlbum
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        picker.cameraCaptureMode = .photo
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let padre: SelectorCamara

        init(_ padre: SelectorCamara) {
            self.padre = padre
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let imagen = info[.originalImage] as? UIImage {
                padre.alTomarFoto(imagen)
            } else {
                padre.alCancelar()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            padre.alCancelar()
        }
    }
}

// MARK: - Pantalla de captura

/// Pantalla de captura de foto.
/// Si la cámara no está disponible (simulador) o el permiso fue denegado,
/// permite elegir la imagen desde la fototeca con `PhotosPicker`.
struct CapturaFotoView: View {
    var alTomarFoto: (UIImage) -> Void
    var alCancelar: () -> Void

    @State private var itemFoto: PhotosPickerItem?
    @State private var permiso: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

    private var hayCamara: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }
    private var permisoConcedido: Bool { permiso == .authorized }

    var body: some View {
        ZStack {
            Color.fondo.ignoresSafeArea()

            if hayCamara && permisoConcedido {
                SelectorCamara(alTomarFoto: alTomarFoto, alCancelar: alCancelar)
                    .ignoresSafeArea()
            } else {
                opcionesAlternativas
            }

            VStack {
                Spacer()
                HStack {
                    Button(action: alCancelar) {
                        Text("✖️ Cancelar")
                            .font(.subtitulo)
                            .foregroundStyle(Color.textoPrimario)
                            .padding(.horizontal, Espaciado.grande)
                            .frame(minHeight: DesignSystem.altoBoton)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(Espaciado.grande)
            }
        }
        .onAppear(perform: pedirPermiso)
        .onChange(of: itemFoto) { _, nuevo in
            guard let nuevo else { return }
            Task {
                if let datos = try? await nuevo.loadTransferable(type: Data.self),
                   let imagen = UIImage(data: datos) {
                    await MainActor.run { alTomarFoto(imagen) }
                }
            }
        }
    }

    // MARK: - Alternativas sin cámara

    private var opcionesAlternativas: some View {
        VStack(spacing: Espaciado.grande) {
            Spacer()

            Text("📷")
                .font(.system(size: 64))

            Text(hayCamara ? "Sin permiso para la cámara" : "Cámara no disponible")
                .font(.titulo)
                .foregroundStyle(Color.textoPrimario)
                .multilineTextAlignment(.center)

            Text("Puedes tomar la foto desde la fototeca del teléfono.")
                .font(.cuerpo)
                .foregroundStyle(Color.textoSecundario)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Espaciado.xl)

            PhotosPicker(selection: $itemFoto, matching: .images, photoLibrary: .shared()) {
                HStack(spacing: Espaciado.medio) {
                    Text("🖼️").font(.system(size: 26))
                    Text("Elegir de la fototeca")
                        .font(.titulo)
                }
                .foregroundStyle(Color.textoSobreAcento)
                .padding(.horizontal, Espaciado.grande)
                .frame(maxWidth: .infinity, minHeight: DesignSystem.altoBotonHero)
                .background(Color.acento, in: RoundedRectangle(cornerRadius: Radio.grande, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Espaciado.grande)

            if hayCamara && permiso == .denied {
                Text("Activa la cámara en Ajustes del iPhone para tomar fotos.")
                    .font(.etiqueta)
                    .foregroundStyle(Color.aviso)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Espaciado.grande)
            }

            Spacer()
        }
        .padding(.vertical, Espaciado.xl)
    }

    // MARK: - Permisos

    private func pedirPermiso() {
        guard hayCamara else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permiso = .authorized
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { concedido in
                DispatchQueue.main.async {
                    permiso = concedido ? .authorized : .denied
                }
            }
        default:
            permiso = .denied
        }
    }
}
