# cursosIpad

App nativa para iPad/iPhone + app companion en Mac para copiar, organizar y
consumir cursos con seguimiento de progreso.

> **Status:** en planificación. Aún no hay código fuente — ver
> [`plan.md`](./plan.md) para el diseño funcional completo y el plan de
> implementación por fases.

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
├── .gitignore
└── (próximamente) CursosIpad.xcodeproj ← Fase 0
    ├── iOS/                             ← target iOS
    ├── macOS/                           ← target macOS
    └── Shared/                          ← Swift Package con modelos comunes
```

## Requisitos

- **macOS** 14 (Sonoma) o superior.
- **Xcode** 15 o superior (Swift 5.9, SwiftUI iOS 17+ / macOS 14+).
- **Dispositivo Apple** (iPhone o iPad) para sideload, o simulador para
  pruebas rápidas.
- **Cuenta de Apple Developer** (opcional — sin ella, el sideload expira a
  los 7 días).

## Cómo correr (cuando exista el proyecto Xcode)

Aún no hay proyecto — eso es la **Fase 0** del plan. Cuando exista:

1. Abrir `CursosIpad.xcodeproj` en Xcode.
2. Seleccionar el target iPad o iPhone físico (o simulador).
3. Build & Run (`⌘R`).
4. Si es dispositivo físico y no tienes cuenta de developer, firmar con
   tu Apple ID personal: Xcode → Settings → Accounts → "+" Apple ID.

Para la app macOS companion: seleccionar el target macOS y `⌘R`.

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