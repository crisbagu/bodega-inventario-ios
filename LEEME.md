# Bodega — app de inventario para iPhone

App **100 % offline** para controlar las entradas y salidas de una bodega de licores.
Todo vive dentro del iPhone: datos, fotos, historial y aprendizaje. Sin internet, sin
nube, sin cuentas, sin suscripciones.

---

## 1. Cómo instalarla en tu iPhone (una sola vez)

Todo está publicado en GitHub: **https://github.com/crisbagu/bodega-inventario-ios**

El archivo compilado está en la sección **Releases** → *app* → `Bodega-unsigned.ipa`.
La página de instalación con los pasos está en
**https://crisbagu.github.io/bodega-inventario-ios/**

### Opción A · Solo el iPhone (sin Mac, sin Xcode) — la recomendada

1. Instala **SideStore** desde el App Store.
2. En SideStore: **⋮ → Sources → Add Source**, y pega:
   `https://raw.githubusercontent.com/crisbagu/bodega-inventario-ios/main/Sitio/fuente.json`
3. Toca **Bodega** → **+** → **Install**. SideStore firma con tu cuenta de Apple y la instala.
4. La primera vez, activa el **Modo desarrollador**: Ajustes → Privacidad y seguridad → Modo desarrollador.

### Opción B · Sideloadly o AltStore en la Mac

1. Descarga el `.ipa` desde el enlace de arriba.
2. **Sideloadly**: arrastra el archivo → tu Apple ID → **Start**.
3. **AltStore**: **⋮ → Install** → tu Apple ID → **Install**.

### Opción C · TrollStore (instalación permanente)

Si tu iPhone tiene iOS 16.0 – 16.6.1 o 17.0, instala TrollStore y añade el `.ipa`.
Sin firmar y sin caducar.

**Sobre la cuenta gratuita de Apple:** la app se instala y funciona igual, pero el
"certificado de desarrollo" gratis dura 7 días. Pasados los 7 días, vuelve a instalarla
(un clic en SideStore). Con la cuenta de pago (99 USD/año) el certificado dura 1 año.

### Opción D · Con Xcode en tu Mac

Abre `Bodega.xcodeproj`, marca *Automatically manage signing*, elige tu cuenta de Apple,
pon un *Bundle Identifier* único (`com.tunombre.bodega`) y pulsa ▶️.

---

## 2. Cómo se usa (en la bodega)

| Acción | Cómo |
|---|---|
| **Entrada / Salida** | Botones grandes en Inicio. Toca → se abre la cámara → toma la foto → la app reconoce el producto. |
| **Reconocimiento** | Código de barras → texto de la etiqueta → color de botella → parecido visual. Cada acierto suma puntos y se muestra el **% de confianza**. Con 90 % o más, un toque y listo. |
| **Aprende solo** | Si corriges una sugerencia, la foto queda como referencia de esa variante y la app mejora con el uso. |
| **Historial** | Cada entrada y salida queda con fecha, hora, usuario, cantidad y su foto. Se puede deshacer el último o anular un movimiento con motivo (sin borrar el historial). |
| **Fotos** | La galería agrupa las fotos por producto, en orden alfabético, con el contador de fotos de cada grupo. |
| **Reportes** | Qué sale más, qué sale menos, qué se está agotando, resumen diario y semanal. |
| **Copia de seguridad** | En Ajustes: **Exportar copia** genera un ZIP (datos + fotos) que guardas en Archivos, iCloud Drive o AirDrop. **Restaurar** lo devuelve todo si cambias de teléfono. |

---

## 3. Reglas que la app respeta

- **Nunca se mezclan conteos** de dos variantes distintas (375 ml y 750 ml son apartados).
- **El stock nunca queda negativo**: si una salida lo dejaría en menos de cero, la app avisa y pide confirmación.
- **Detecta duplicados**: si registras lo mismo dos veces en pocos segundos, te pregunta antes.
- **Todo en mililitros por dentro**, pero se muestra en ml o en litros (375 ml = 0,375 L) como prefieras.
- **Los datos de ejemplo** se pueden borrar desde Ajustes.

---

## 4. Verificación hecha (y qué falta)

Lo que **sí** está comprobado en esta máquina (sin Xcode):
- **Sintaxis**: los 32 archivos Swift pasan `swiftc -parse` sin un solo error.
- **Lógica de dominio**: 40/40 pruebas **ejecutadas y en verde** con el arnés de `Verificacion/`
  (conversiones ml↔L, lectura de etiqueta, motor de probabilidades, descarte de 375 vs 750 ml,
  aprendizaje por uso, color dominante, país de origen).
- **Proyecto Xcode**: generado con `Tools/generar_xcodeproj.py` y validado con `plutil`.
- **Servicios**: ZIP con `Compression` verificado con `unzip -t` (compatible con el Finder y
  con el archivador de iOS), CSV con BOM (Excel en español), redimensionado real de fotos.
- **Interfaz**: type-check completo contra SwiftUI/Charts reales, 0 errores.

Lo que **no** se puede comprobar aquí (no hay Xcode ni iPhone en esta máquina):
- La compilación final para iOS y la instalación en el teléfono.
- La cámara real y la calidad del OCR con botellas de tu bodega (depende de la luz y del ángulo).

Para compilar en tu Mac: `bash Tools/verificar_proyecto.sh` (reviso + pruebas) y luego
abre `Bodega.xcodeproj` en Xcode.

---

## 5. Estructura del proyecto

```
BodegaApp/
  Bodega/
    App/        punto de entrada y pestañas
    Core/       modelos SwiftData, unidades, catálogo, preferencias
    Vision/     OCR, código de barras, color y motor de coincidencia
    Services/   fotos, stock, copia de seguridad, exportación
    UI/         pantallas y sistema de diseño
  BodegaTests/  pruebas unitarias (target de Xcode)
  Verificacion/ arnés que corre en macOS sin Xcode
  Tools/        generador del proyecto y verificador
```
