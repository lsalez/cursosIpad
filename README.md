# cursosIpad

App nativa para iPad/iPhone + app companion en Mac para copiar, organizar y
consumir cursos con seguimiento de progreso.

> **Status:** Fase 0 (Andamiaje) completa. Las apps iOS y macOS compilan y
> abren un "Hola mundo". Ver [`plan.md`](./plan.md) para el diseño funcional
> completo y el plan de implementación por fases.

## ¿Qué hace?

Hoy los cursos descargados viven en una Mac, en una carpeta con archivos
sueltos (videos, PDFs, HTMLs). Verlos en el iPad implica copiarlos a mano,
no hay forma de saber dónde quedaste, y volver a encontrar el curso entre
todos los demás es un dolor de cabeza.

`cursosIpad` resuelve eso con dos apps pequeñas:

- **App iOS** — biblioteca, reproductor de video, visor de PDF y HTML,
  búsqueda full-text en subtítulos y HTMLs, y progreso por curso.
- **App macOS** — editor de cursos (renombrar, reordenar, portada,
  etiquetas) y puente de transferencia por WiFi (Bonjour).

La transferencia por USB desde Finder queda cubierta automáticamente al
exponer la carpeta de cursos de la app iOS en la app Archivos.

## Estructura del proyecto

```
cursosIpad/                              ← monorepo
├── README.md                            ← este archivo
├── plan.md                              ← diseño + fases de implementación
├── project.yml                          ← spec de xcodegen (fuente de verdad)
├── CursosIpad.xcodeproj/                ← generado por xcodegen desde project.yml
├── iOS/                                 ← target iOS (CursosIpad)
├── macOS/                               ← target macOS (CursosIpadMac)
└── Shared/                              ← Swift Package local con modelos comunes
    └── Sources/Shared/
        ├── Models/                      ← Fase 1
        ├── Sidecar/                     ← Fase 5
        └── TransferProtocol/            ← Fase 11
```

## Requisitos

- **macOS** 14 (Sonoma) o superior.
- **Xcode** 15 o superior (Swift 5.9, SwiftUI iOS 17+ / macOS 14+).
- **[xcodegen](https://github.com/yonaskolb/XcodeGen)** 2.45 o superior
  (opcional — solo si quieres regenerar el `.xcodeproj` desde
  `project.yml`; el `.xcodeproj` ya viene commiteado).
- **Dispositivo Apple** (iPhone o iPad) para sideload, o simulador para
  pruebas rápidas.
- **Cuenta de Apple Developer** (opcional — sin ella, el sideload expira a
  los 7 días).

## Cómo correr

1. Abrir `CursosIpad.xcodeproj` en Xcode.
2. Seleccionar el scheme `CursosIpad` (iOS) o `CursosIpadMac` (macOS).
3. Elegir destino: un iPad / iPhone físico, un simulador o "My Mac".
4. Build & Run (`⌘R`).
5. Si es dispositivo físico y no tienes cuenta de developer, firmar con
   tu Apple ID personal: Xcode → Settings → Accounts → "+" Apple ID.

La app iOS actualmente muestra un placeholder "cursosIpad / Fase 0 —
Andamiaje". Lo mismo la app macOS. La lógica de producto entra a partir
de la Fase 1.

### Regenerar el proyecto (opcional)

El `.xcodeproj` está commiteado. Si modificas `project.yml` o
`iOS/` / `macOS` / `Shared/` en su estructura, regenera con:

```sh
xcodegen generate
```

Si no tienes xcodegen: `brew install xcodegen`.

## Stack técnico (resumen)

- **Lenguaje:** Swift 5.9+
- **UI:** SwiftUI (iOS 17+, macOS 14+)
- **Persistencia:** sidecar JSON por curso (`.cursosIpad.json`) + SQLite
  FTS5 para búsqueda
- **Visores:** AVKit (video), PDFKit, WKWebView (todos nativos)
- **Red local:** `Network.framework` (NWListener + NWBrowser para Bonjour)
- **Transferencia HTTP iOS:** Swifter (a decidir)
- **Empaquetado ZIP:** ZIPFoundation (a decidir)

Detalles completos y justificaciones en [`plan.md`](./plan.md) §7.

## Documentación

- [`plan.md`](./plan.md) — el documento principal. Cubre funcionalidad,
  arquitectura, modelos de datos, UI detallada, fases de implementación y
  riesgos abiertos.

## Licencia

Privado, sin licencia pública por ahora.
