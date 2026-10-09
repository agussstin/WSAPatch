# Vlog Editor (iOS)

App de iOS (SwiftUI + AVFoundation, iOS 17+) para editar vlogs fácilmente.

## Funciones

- Importar varios videos de la galería y ordenarlos.
- Recortar inicio/final y dividir clips.
- **Cortes automáticos**: detecta y quita silencios (por clip o en todos).
- Volumen por clip (0–200 %).
- Música de fondo desde tus archivos (Archivos/iCloud), en bucle, con volumen y fade-out final. Sin restricciones: tú eliges la música.
- Formato 9:16 (vertical) o 16:9; vista previa en vivo.
- Exportar en MP4 y guardar en la galería.

## Cómo abrirlo (necesitas un Mac con Xcode 15+)

```sh
brew install xcodegen
cd VlogEditor-iOS
xcodegen          # genera VlogEditor.xcodeproj desde project.yml
open VlogEditor.xcodeproj
```

En Xcode, elige tu equipo en *Signing & Capabilities* y cambia el bundle id
(`com.example.VlogEditor`) por uno tuyo. Prueba en un iPhone real o en el simulador.

> Este código se escribió sin poder compilarlo (entorno Linux), así que es posible
> que haya que corregir algún detalle menor en la primera compilación.

## Estructura

- `Models/Models.swift`: clip, música, formatos.
- `Services/SilenceDetector.swift`: detección de silencios.
- `Services/CompositionBuilder.swift`: arma la composición, mezcla de audio, exportación.
- `Services/EditorViewModel.swift`: estado y acciones del editor.
- `Views/`: interfaz SwiftUI.
