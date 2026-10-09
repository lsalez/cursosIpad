# Plan — `cursosIpad`

App nativa para iPad/iPhone + app companion en Mac para copiar, organizar y
consumir cursos con seguimiento de progreso.

> Documento de **funcionalidad y arquitectura**. No incluye código todavía.
> Cualquier decisión abierta está marcada con **⚠️ por decidir**.

---

## Progreso

**Fase actual:** Fase 11 — Transferencia por WiFi · **% global:** 78% · **Última act.:** 2026-10-09

| # | Fase | Estado | Cerrada |
|---|------|--------|---------|
| 0 | Andamiaje | ✅ | 2026-10-08 |
| 1 | Indexador de cursos (iOS) | ✅ | 2026-10-08 |
| 2 | Biblioteca iOS | ✅ | 2026-10-08 |
| 3 | Detalle del curso | ✅ | 2026-10-08 |
| 4 | Búsqueda full-text | ✅ | 2026-10-08 |
| 5 | Sidecar + progreso | ✅ | 2026-10-08 |
| 6 | Reproductor de video | ✅ | 2026-10-08 |
| 7 | Visor PDF | ✅ | 2026-10-08 |
| 8 | Visor HTML | ✅ | 2026-10-08 |
| 9 | Biblioteca macOS + importador | ✅ | 2026-10-09 |
| 10 | Editor de curso (Mac) | ✅ | 2026-10-09 |
| 11 | Transferencia por WiFi | ⬜ | — |
| 12 | Detección por USB | ⬜ | — |
| 13 | Pulido | ⬜ | — |

**Estados:** ⬜ pendiente · 🔄 en progreso · ✅ cerrada

> **Claude cierra las fases** (no el usuario). Se hace cuando se cumple
> todo lo siguiente:
>
> 1. El checklist de la fase (en §18) está 100% verde (`- [x]`).
> 2. El **Entregable** de la fase está verificado — no solo compilando,
>    sino comprobado de verdad (ver regla en memoria `verify-after-implement`).
> 3. El usuario da luz verde explícita ("cierra Fase N") o implícita
>    al pedir continuar a la siguiente fase (por ejemplo, "commitea y
>    prosigue" cuando la implementación + verificación ya estén verdes).
>
> Acciones concretas al cerrar:
>
> - Cambiar `⬜` por `✅` en la fila correspondiente de esta tabla.
> - Poner la fecha ISO (`AAAA-MM-DD`) en la columna "Cerrada".
> - Actualizar la línea superior: **Fase actual** → la siguiente;
>   **% global** → `floor(fasesCerradas / totalFases × 100)` (si es la
>   última fase del MVP, `% global = 100`); **Última act.** → hoy.
> - Si la fase entró en `🔄` mientras se trabajaba en ella, transicionar
>   a `✅` al cerrar.
> - Commitar el cambio con tipo `docs:`, por ejemplo
>   `docs: close Fase 0 (Andamiaje)`.
> - Si aparecen fases nuevas (caso excepcional), agregarlas al final de
>   la tabla con estado `⬜`.

---

## 1. Visión

Resolver un problema concreto: hoy los cursos descargados viven en una Mac,
en una carpeta con archivos sueltos. Verlos en el iPad/iPhone implica copiarlos
a mano, no hay forma de saber dónde quedaste, y volver a encontrar el curso es
un dolor de cabeza.

`cursosIpad` ataca eso con dos apps pequeñas:

- **App iOS** — biblioteca, reproductor, visor, búsqueda y progreso.
- **App macOS** — editor de cursos y puente de transferencia por WiFi.

La transferencia por USB desde Finder queda cubierta por la propia app iOS
expuesta en la app Archivos, sin código extra.

---

## 2. Decisiones de producto (cerradas)

| # | Decisión | Implicación |
|---|----------|-------------|
| 1 | App iOS nativa con **Swift + SwiftUI** | Mejor UX, acceso a AVKit/PDFKit/WebKit. Requiere Mac con Xcode para compilar. |
| 2 | App macOS también nativa con **SwiftUI** | Comparte modelos y protocolo de transferencia con la iOS. |
| 3 | Distribución **solo local** (sideload con Xcode) | Sin App Store ni TestFlight por ahora. Caduca cada 7 días con firma gratuita, 1 año con cuenta de developer. |
| 4 | Transferencia por **WiFi (app Mac)** y por **USB (Finder/Archivos)** | Dos caminos válidos. WiFi para comodidad, USB para lotes grandes o sin WiFi común. |
| 5 | Contenido de los cursos: **video, PDF y HTML** | Cada tipo tiene su visor nativo en iOS. |
| 6 | Progreso **por archivo + estado completado** | Cada video/PDF/HTML guarda su avance y se puede marcar como terminado. La app muestra un porcentaje global del curso. |
| 7 | App Mac = **editor completo de cursos** | Antes de transferir, se pueden reorganizar archivos, renombrar, poner portada, etc. |
| 8 | Cursos viven en **carpeta visible en la app Archivos del iPad** | El usuario los ve y los puede respaldar/mover desde la app Archivos. |
| 9 | Búsqueda **por nombre + full-text en subtítulos y HTMLs** (no PDFs) | Indexa `.srt`/`.vtt` y texto de `.html` en SQLite FTS5 local. Sin red. |
| 10 | Soporte **tema claro y oscuro** con override manual | Sigue el sistema por default. Toggle en Ajustes: Sistema / Claro / Oscuro. Colores semánticos en toda la app. |
| 11 | **Paleta de marca fija** para chrome (inspirada en SPID) + **CTA dinámico** por curso | Menús, fondos y textos usan paleta SPID. El botón "Continuar aprendiendo" toma color de la portada del curso (ajustado al tema). |

---

## 3. Personas y casos de uso

### Persona única: "estudiante con cursos descargados"

Tiene cursos en una Mac (carpetas con videos, PDFs, HTMLs). Quiere verlos en el
iPad mientras viaja, en el celu cuando está fuera, y que la app recuerde
dónde se quedó en cada uno.

### Casos de uso principales

1. **Copiar un curso nuevo desde la Mac por WiFi**
   - Abro la app Mac, elijo la carpeta del curso en mi biblioteca.
   - La app detecta mi iPad automáticamente (Bonjour).
   - Toco "Enviar" y la copia aparece en el iPad.
2. **Copiar varios cursos por USB desde Finder**
   - Conecto el iPad a la Mac por cable.
   - En Finder, abro la sección del iPad > Archivos > `cursosIpad`.
   - Arrastro carpetas de cursos.
   - La app iOS los detecta al abrirla y los indexa.
3. **Ver mi biblioteca**
   - Abro la app iOS, veo una cuadrícula con todos mis cursos (portada + título + porcentaje).
4. **Reanudar un curso**
   - Toco un curso, me lleva al último archivo que abrí (video en el segundo
     exacto, PDF en la página exacta).
5. **Marcar como completado**
   - Botón "marcar como visto" en el reproductor / visor.
6. **Buscar un curso**
   - Toco la lupa, escribo "phyton" (o "python"), aparece el curso.
7. **Editar un curso antes de mandarlo (en la Mac)**
   - Quito archivos duplicados, reordeno módulos, pongo portada, renombro.

---

## 4. Alcance MVP

### App iOS
- [ ] Pantalla de bienvenida + selector inicial (informativo).
- [ ] Biblioteca estilo catálogo Udemy: grid con cover 16:9, título, barra
      de progreso, micro-badge "Continuar".
- [ ] Chips de etiquetas arriba para filtrar por tag.
- [ ] Búsqueda por nombre de curso (barra `.searchable`).
- [ ] Orden de biblioteca (recientes, A-Z, por avance).
- [ ] **Búsqueda full-text en subtítulos y HTMLs** (ver §16):
  - [ ] Indexador SQLite FTS5 en background (`Library/Application Support/cursosIpad-index/index.sqlite`).
  - [ ] Extraer texto de `.srt`/`.vtt` (cues con timestamp).
  - [ ] Extraer texto de `.html`/`.htm` con `NSAttributedString`.
  - [ ] Indexación incremental por `mtime`, cancellable.
  - [ ] Resultados con snippet resaltado + timestamp (subs) / posición (HTML).
  - [ ] Tap en resultado abre la lección en esa posición.
- [ ] Detalle del curso estilo "course landing": hero con cover + CTA
      "Continuar aprendiendo" o "Empezar curso" + tabs (Contenido / Descripción / Archivos).
- [ ] Currículum con módulos colapsables, ícono por tipo, palomita si completo,
      duración en videos, highlight del último visto.
- [ ] Extracción de color dominante de la portada para el botón primario
      (con ajuste por tema, ver §14.1.1).
- [ ] **Paleta de marca SPID para chrome** (ver §14.1.1):
  - [ ] Tokens `appBackground`, `appMenu`, `appTitle`, `appInfo`, `appDivider`
        con variantes para modo claro y oscuro.
  - [ ] Tipografía SF Pro Rounded con jerarquía marcada.
  - [ ] `UIColor(dynamicProvider:)` para el accent dinámico por curso.
- [ ] iPad: `NavigationSplitView` (biblioteca a la izquierda, detalle/visor a la derecha).
- [ ] iPad en visores: layout split (visor a la izquierda, currículum a la derecha).
- [ ] Reproductor de video nativo (AVKit) con:
  - [ ] Reanudar en el último segundo visto.
  - [ ] Botón "marcar como completado" + toast al 95% (**⚠️ por decidir** auto-completar).
  - [ ] Controles estándar (play/pause, scrub, velocidad).
  - [ ] PiP en iPad.
- [ ] AirPlay (botón automático en controles AVKit; requiere
      `UIBackgroundModes = audio` en Info.plist para background playback;
      `allowsExternalPlayback = true` en `AVPlayer`).
- [ ] Miniaturas de video (ver §13):
  - [ ] Detección y uso de miniaturas provistas (`<video>.jpg`).
  - [ ] Auto-generación al 25% con `AVAssetImageGenerator` en background.
  - [ ] Caché en `.thumbs/` (no se transfiere por WiFi).
  - [ ] Mostrar miniatura en currículum y pestaña Archivos.
- [ ] Visor de PDF nativo (PDFKit) con:
  - [ ] Reanudar en la última página.
  - [ ] Botón "marcar como completado".
  - [ ] Toggle miniaturas.
- [ ] Visor de HTML nativo (WKWebView) con:
  - [ ] Reanudar al final del scroll (última posición).
  - [ ] Botón "marcar como completado".
  - [ ] Links relativos a archivos de la misma carpeta funcionando.
- [ ] Persistencia del progreso en disco (sidecar JSON por curso).
- [ ] Detección automática de cursos nuevos cuando se agregan archivos por USB.
- [ ] **Tema claro y oscuro** (ver §2 #10 y §14.1):
  - [ ] Toda la UI con colores semánticos (sigue el sistema por default).
  - [ ] Toggle en Ajustes: Sistema / Claro / Oscuro.
  - [ ] Color de acento dinámico (de portada) ajusta variante por tema
    (más oscuro en claro, más claro en oscuro).
  - [ ] Cubiertas, miniaturas y videos se muestran igual en ambos temas.
- [ ] Deep link al último archivo visto del curso.

### App macOS
- [ ] Biblioteca local: lista de cursos disponibles en la Mac.
- [ ] Importar un curso: arrastrar carpeta o "abrir carpeta".
- [ ] Editor de curso:
  - [ ] Reordenar archivos y módulos (drag & drop).
  - [ ] Renombrar archivos y módulos.
  - [ ] Eliminar archivos no deseados.
  - [ ] Definir portada (auto-detección o manual).
  - [ ] Editar título del curso.
  - [ ] Editar **etiquetas** (chip input estilo Mail).
  - [ ] **"Fijar este frame como miniatura"** desde el preview de video.
- [ ] Detección del iPad por Bonjour.
- [ ] Transferencia por WiFi con barra de progreso y velocidad.
- [ ] Manejo de conflictos (curso ya existe, sobrescribir / saltar / fusionar).

### Común
- [ ] Estructura de carpetas esperada para un curso (auto-detección de módulos).
- [ ] Sidecar `.cursosIpad.json` con metadatos y progreso.
- [ ] Detección de tipo de archivo por extensión.

---

## 5. Fuera de alcance (por ahora)

- Sincronización en la nube entre varios iPads.
- Cuentas de usuario / login.
- Notas, marcadores dentro de videos, transcripciones.
- Subtítulos: la app respeta los `.srt`/`.vtt` que existan junto al video
  (los usa para mostrar y para búsqueda), pero **no los descarga** ni los
  genera automáticamente.
- **Búsqueda dentro del contenido de PDFs.** (Sí se busca en subtítulos y HTMLs, ver §16.)
- Búsqueda dentro de subtítulos embebidos en `.mp4` (solo se indexan los `.srt`/`.vtt` sidecar).
- Búsqueda difusa (typos).
- Comentarios o comunidad.
- Descarga desde plataformas (Udemy, Coursera, etc.).
- Conversión de formatos (todo se reproduce tal cual está en disco).
- DRM o protección de los cursos.
- Versión iPad con multi-ventana / Split View específica.
- Apple Pencil / interacciones stylus.
- Atajos de Siri, widgets de pantalla principal.

---

## 6. Arquitectura

```
┌──────────────────────────────────────────────────────────────────────┐
│                              iPad / iPhone                            │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │                       App iOS (SwiftUI)                       │    │
│  │                                                               │    │
│  │  Biblioteca ─▶ Visor PDF ─▶ Visor HTML ─▶ Reproductor Video    │    │
│  │      │                                                        │             │    │
│  │      ▼                                                        │             │    │
│  │  Indexador de cursos (escanea Documents/)                      │             │    │
│  │      │                                                        │             │    │
│  │      ▼                                                        │             │    │
│  │  Lector/escritor del sidecar .cursosIpad.json                  │             │    │
│  └──────────────────────────────────────────────────────────────┘    │
│      ▲                                                             ▲    │
│      │ lee/escribe archivos en                                      │    │
│      ▼ Documents/ (expuesto en app Archivos + WiFi server)         │    │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │  Servidor HTTP local (solo cuando recibe transferencia)        │    │
│  │  Anuncia servicio Bonjour _cursosipad._tcp                    │    │
│  └──────────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────┘
                                  ▲ Bonjour + HTTP en LAN
┌──────────────────────────────────────────────────────────────────────┐
│                                  Mac                                  │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │                     App macOS (SwiftUI)                       │    │
│  │                                                               │    │
│  │  Editor de cursos ─▶ Cliente HTTP ─▶ Descubridor Bonjour     │    │
│  │      │                              │                         │    │
│  │      ▼                              ▼                         │    │
│  │  Lee archivos de            POST /api/courses                 │    │
│  │  ~/Movies/Cursos/...        multipart/form-data               │    │
│  └──────────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────┘
```

**Puntos clave de la arquitectura:**

- La app iOS es la **fuente de verdad** del progreso. La Mac solo edita y transfiere.
- La transferencia por WiFi es **push** desde la Mac a la iPad. El iPad expone un endpoint.
- El sidecar `.cursosIpad.json` se escribe **dentro** de la carpeta del curso, así si la cantidad de cursos se mueve o respalda, el progreso va con ellos.
- No hay base de datos central: la base es el filesystem + el JSON sidecar.

---

## 7. Stack técnico

| Capa | Tecnología | Razón |
|------|-----------|-------|
| Lenguaje | Swift 5.9+ | Requisito para SwiftUI moderno. |
| UI iOS | SwiftUI (iOS 17+) | Declarativo, rápido de iterar. Colores semánticos para soportar tema claro/oscuro. Tokens `Color` con paleta SPID (ver §14.1.1). |
| UI macOS | SwiftUI (macOS 14+) | Misma base de código mental. También soporta tema y misma paleta. |
| Persistencia | **Sidecar JSON** en cada carpeta de curso | Portable, sin Core Data, fácil de respaldar. |
| Reproductor de video | AVKit / AVPlayer | Nativo, gratis, soporta todo lo necesario. |
| Visor PDF | PDFKit | Nativo. |
| Visor HTML | WKWebView | Nativo. |
| Red local (Bonjour) | `Network.framework` (NWBrowser/NWListener) | API moderna y oficial. |
| Servidor HTTP en iOS | **Swifter** (paquete SPM) | Servidor HTTP minimalista en Swift. Alternativa: construir uno propio con NWListener. **⚠️ por decidir** |
| Cliente HTTP en macOS | `URLSession` | Ya incluido, soporta multipart con progreso. |
| Empaquetado de cursos para transferencia | ZIP estándar (PKZip) vía **ZIPFoundation** (paquete SPM) | Reduce overhead de HTTP para muchos archivos. **⚠️ por decidir** (alternativa: enviar archivo por archivo). |
| Descubrimiento de archivos en iOS | `FileManager` + escaneo recursivo | Sin librería externa. |
| Búsqueda full-text | **SQLite FTS5** (built-in, sin paquete) | Índice local de subtítulos + HTMLs. Vive en app sandbox. |

---

## 8. Estructura del proyecto Xcode

Proyecto único con dos apps + un paquete compartido.

```
cursosIpad/                              ← raíz del repo
├── plan.md                              ← este documento
├── README.md                              ← guía rápida en español
├── CursosIpad.xcodeproj                 ← proyecto Xcode
├── iOS/                                  ← target iOS
│   ├── CursosIpadApp.swift              ← @main
│   ├── Views/                           ← pantallas SwiftUI
│   ├── ViewModels/
│   ├── Library/                         ← indexador, sidecar, modelos
│   ├── Player/                          ← AVKit/PDFKit/WKWebView wrappers
│   ├── Server/                          ← servidor HTTP + Bonjour
│   ├── Resources/
│   │   └── Info.plist                   ← permisos (local network, file sharing)
│   └── Assets.xcassets
├── macOS/                                ← target macOS
│   ├── CursosIpadMacApp.swift           ← @main
│   ├── Views/
│   ├── Editor/                          ← editor de cursos
│   ├── Client/                          ← cliente HTTP + Bonjour
│   └── Resources/
├── Shared/                               ← Swift Package local (modelos + protocolo)
│   ├── Package.swift
│   └── Sources/Shared/
│       ├── Models/                      ← Course, CourseItem, Progress
│       ├── Sidecar/                     ← codable para .cursosIpad.json
│       └── TransferProtocol/            ← contrato HTTP + esquema multipart
└── docs/                                 ← material de apoyo
```

**Por qué un paquete compartido:** los modelos `Course`, `CourseItem`, etc. y el
esquema del sidecar JSON se usan idénticos en ambas apps. Un SPM local evita
duplicarlos y mantiene el contrato único.

---

## 9. Estructura en disco de un curso

El usuario prepara una carpeta así (o la app Mac lo ayuda a armarla):

```
Mi Curso de Python/                       ← nombre = título del curso
├── cover.jpg                             ← portada (opcional, auto-detecta)
├── .cursosIpad.json                      ← sidecar (auto-generado por la app)
├── 01 Introduccion/                      ← módulos = subcarpetas de primer nivel
│   ├── bienvenido.mp4
│   ├── diapositivas.pdf
│   └── recursos.html
├── 02 Tipos de datos/
│   ├── clase-1.mp4
│   ├── ejercicios.pdf
│   └── cheatsheet.html
└── 03 Funciones/
    ├── clase-2.mp4
    └── ...
```

### Reglas de detección

- **Curso:** cualquier carpeta de primer nivel dentro de `Documents/` (en iOS) o de la carpeta de biblioteca de la Mac. Cada carpeta de curso queda directamente en la raíz de `Documents/`, no anidada en una subcarpeta intermedia — eso hace que arrastrar desde Finder/Archivos quede donde el indexador mira (ver §19, decisión cerrada de ruta).
- **Módulo:** cada subcarpeta de primer nivel del curso. Los archivos sueltos en la raíz forman un "módulo" virtual llamado "General" (o no se agrupan — **⚠️ por decidir**).
- **Tipo de archivo por extensión:**
  - Video: `.mp4 .mov .m4v .webm`
  - PDF: `.pdf`
  - HTML: `.html .htm`
  - Ignorar todo lo demás (`.DS_Store`, `.srt`, imágenes sueltas, etc.).
- **Portada:** `cover.jpg`, `cover.png`, o la primera imagen encontrada en la raíz. Si no hay, se genera un placeholder con la inicial del título.
- **Etiquetas (`tags`):** opcionales. Se editan en la app Mac (no se infieren del nombre de carpeta). Sirven para filtrar en la biblioteca.
- **Miniaturas de video:** ver §13. Convención: `<video>.jpg` junto al `.mp4` (provista) o `.thumbs/<ruta>.jpg` (auto-generada). La app iOS prefiere provista, si no, auto-genera.
- **Carpeta `.thumbs/`:** auto-generada por la app iOS, no se transfiere por WiFi (se regenera localmente). Se puede ignorar / borrar sin perder funcionalidad.
- **Sidecar:** se crea automáticamente al primer indexado. Si no existe, el curso todavía se ve pero sin progreso.

---

## 10. Protocolo de transferencia por WiFi

### Descubrimiento

- La app iOS, al entrar a "modo recibir" (automático al abrir la app, o
  manual con un toggle), levanta un `NWListener` TCP en un puerto aleatorio
  y publica un servicio Bonjour de tipo `_cursosipad._tcp`.
- La app macOS usa `NWBrowser` para encontrar todos los servicios
  `_cursosipad._tcp` en la red local y los muestra como dispositivos
  disponibles.

### Endpoints HTTP en la app iOS

```
POST   /api/courses                       ← sube un curso completo (multipart)
GET    /api/ping                          ← chequeo de salud (devuelve versión)
```

### Esquema del multipart

Cada request `POST /api/courses` envía:

| Parte | Content-Type | Descripción |
|-------|-------------|-------------|
| `metadata` | `application/json` | `{ "name": "...", "structure": [...], "version": 1 }` con la lista de rutas de archivos. |
| `payload` | `application/zip` | ZIP con el contenido completo del curso. |

**Por qué ZIP:** transferir miles de archivos por HTTP tiene mucho overhead
(miles de conexiones, milisegundos por archivo). Un solo ZIP baja mucho el
tiempo total. La iPad lo descomprime en su `Documents/<nombre>/`
(raíz del sandbox, sin subcarpeta intermedia — ver §9).

### Progreso y retroalimentación

- La app macOS muestra una barra de progreso por curso y velocidad de transferencia.
- La app iOS muestra "Recibiendo 'Mi Curso de Python' (340 MB)".

### Manejo de conflictos

Si el curso ya existe en el iPad:

- **Sobrescribir** — borra el anterior y copia el nuevo (progreso perdido).
- **Saltar** — deja el anterior intacto.
- **Fusionar** ⚠️ por decidir — añadir solo los archivos nuevos. No es trivial.

---

## 11. Modelos de datos

```text
Course
├── id: UUID
├── folderName: String          ← nombre de la carpeta en disco
├── title: String               ← "Mi Curso de Python"
├── coverFileName: String?      ← "cover.jpg"
├── tags: [String]              ← opcional, ej. ["python", "backend"]
├── modules: [Module]
└── totalProgress: Double       ← derivado, % 0.0–1.0

Module
├── id: UUID
├── folderName: String          ← "01 Introduccion"
├── title: String               ← derivado de folderName
└── items: [CourseItem]

CourseItem
├── id: UUID
├── relativePath: String        ← "01 Introduccion/bienvenido.mp4"
├── type: ItemType              ← .video | .pdf | .html
├── title: String               ← derivado del filename
├── sizeBytes: Int64
├── durationSeconds: Double?    ← solo para video
└── progress: ItemProgress

ItemProgress
├── lastViewedAt: Date?
├── positionSeconds: Double?    ← para video y HTML (scroll position en segundos)
├── lastPage: Int?              ← solo para PDF
├── isCompleted: Bool
└── completionMarkedAt: Date?
```

> Los modelos **no** son la fuente de verdad en runtime: la fuente de verdad es
> el filesystem + el sidecar JSON. Los modelos se reconstruyen al indexar.

---

## 12. Sidecar `.cursosIpad.json`

Vive en la raíz de cada curso. Es un único archivo por curso para mantenerlo
simple.

```json
{
  "version": 1,
  "courseId": "uuid-v4",
  "title": "Mi Curso de Python",
  "coverFileName": "cover.jpg",
  "description": "Curso introductorio a Python...",
  "tags": ["python", "backend"],
  "items": {
    "01 Introduccion/bienvenido.mp4": {
      "type": "video",
      "positionSeconds": 1234.5,
      "lastViewedAt": "2026-10-08T12:34:56Z",
      "isCompleted": false
    },
    "01 Introduccion/diapositivas.pdf": {
      "type": "pdf",
      "lastPage": 12,
      "lastViewedAt": "2026-10-08T12:40:11Z",
      "isCompleted": true,
      "completionMarkedAt": "2026-10-08T12:50:00Z"
    },
    "01 Introduccion/recursos.html": {
      "type": "html",
      "positionSeconds": 18.0,
      "lastViewedAt": "2026-10-07T22:01:00Z",
      "isCompleted": false
    }
  }
}
```

**Reglas:**

- Se reescribe completo en cada cambio (es pequeño, no necesita ser
  incremental).
- Si se borra, la app lo regenera vacío en el próximo indexado.
- Si un archivo referenciado en el sidecar ya no existe en disco, se ignora
  silenciosamente.

---

## 13. Miniaturas (thumbnails de video)

Solo aplica a **videos**. PDFs y HTMLs usan el ícono de tipo, no necesitan
miniatura.

### 13.1 Prioridad de búsqueda (de mayor a menor)

1. **Miniatura provista por el usuario** — un archivo con el mismo nombre
   que el video pero extensión de imagen, junto al `.mp4`:
   - `leccion-1.mp4` → `leccion-1.jpg` (acepta `.png`, `.jpeg`).
   - Si existe, gana sobre todo lo demás.
2. **Miniatura auto-generada** — al detectar un video sin miniatura, la app
   iOS extrae un frame al **25% de la duración** con
   `AVAssetImageGenerator`, lo guarda como JPG (320×180, calidad 0.7) en
   `.thumbs/<archivo-directorio>.jpg` dentro del curso y lo cachea en disco.
3. **Placeholder** — ícono neutro con símbolo de play si no hay nada.

### 13.2 Reglas

- **Lazy + background:** la generación ocurre cuando el item se va a
  mostrar por primera vez, en una `Task` fuera del main thread, sin
  bloquear la UI. Cancelable si el usuario navega a otro lado.
- **Una sola vez:** si la miniatura ya existe en `.thumbs/`, se reutiliza;
  nunca se regenera a menos que falte.
- **No se transfiere por WiFi:** las miniaturas auto-generadas son caché
  local del dispositivo y se regeneran en el iPad después de copiar.
  Las miniaturas provistas **sí** se transfieren (son archivos del usuario).
- **Limpieza:** si se elimina un video, su miniatura auto-generada se
  elimina también. Las provistas quedan a criterio del usuario.

### 13.3 Dónde se ven

- **Currículum** (§14.5): miniatura 16:9 mini (~80×45) reemplaza al ícono ▶
  en cada lección de video. PDFs y HTMLs siguen con su ícono de tipo.
- **Pestaña Archivos** (§14.5): miniatura más grande (~200×112) en grid.
- **Detalle del curso:** opcional, una miniatura destacada en la cabecera
  (futuro, no MVP).

### 13.4 Editor de la Mac (bonus)

El panel de preview del editor (§15.2) permite **"fijar este frame como
miniatura"**: el usuario scrubea el video, encuentra el frame que quiere, y
la app exporta ese JPG junto al `.mp4` para que la app iOS lo use como
miniatura provista.

---

## 14. Lenguaje visual y pantallas — App iOS

### 14.1 Referencia visual

La app se inspira en plataformas modernas de cursos tipo **Udemy** y **Platzi**:
cubiertas grandes y coloridas, tipografía fuerte, tarjetas con progreso, un
CTA primario prominente ("Continuar aprendiendo"), y un currículum lateral
con palomitas por lección.

**Principios de diseño:**

- **Cubierta al frente.** El cover es lo más importante. Grande en el
  detalle del curso, mediana en las tarjetas de la biblioteca.
- **Tipografía con jerarquía marcada.** Títulos bold grandes
  (24–34 pt en detalle, 17–20 en tarjetas), SF Pro Rounded/Display.
  Subtítulos en regular, texto secundario en color secundario.
- **Progreso siempre visible.** Barra de progreso debajo de cada tarjeta
  ("6 de 24 lecciones • 25%") y micro-badge "Continuar ▶" si hay último visto.
- **CTA primario dinámico.** Botón grande, lleno, color derivado de la
  portada del curso (color dominante extraído con `UIImage`).
  En el detalle: "Continuar aprendiendo: <lección>" o "Empezar curso".
  El color del CTA **cambia por curso** pero respeta el tema
  (más oscuro en claro, más claro en oscuro para mantener contraste).
- **Chrome con paleta de marca fija.** Menús, navigation bars, fondos y
  textos usan la paleta SPID (ver §14.1.1) — así la app tiene identidad
  reconocible independiente del curso que se esté viendo.
- **Currículum escroleable.** Lista de módulos con lecciones; cada lección
  con ícono de tipo, palomita si está completa, duración si es video.
- **Tema claro y oscuro.** Toda la UI usa colores semánticos. Toggle en
  Ajustes: Sistema / Claro / Oscuro. La paleta tiene variantes para cada
  modo (ver §14.1.1).
- **iPad con `NavigationSplitView`.** Biblioteca a la izquierda, detalle/visor
  a la derecha. Aprovecha el espacio grande con layouts tipo "two-column"
  como en la app de Udemy para iPad.

#### 14.1.1 Paleta de marca (inspirada en SPID)

Dos capas que conviven:

- **Chrome fijo por tema:** menús, navigation bars, fondos, textos —
  siempre la misma paleta, da identidad a la app.
- **Acento dinámico por curso:** botón "Continuar aprendiendo" y micro-badges
  — cambia por curso, da personalidad por curso.

**Modo claro — Chrome**

| Token | Hex | Uso |
|-------|-----|-----|
| `appBackground` | `#EDF2FA` | Fondo general de la app, fondo de tarjetas |
| `appMenu` | `#09184D` | Navigation bars, tab bars, menús laterales |
| `appTitle` | `#2F2E2E` | Títulos, texto principal |
| `appInfo` | `#808085` | Subtítulos, captions, metadata |
| `appDivider` | `#D6DBE5` | Separadores finos |

**Modo oscuro — Chrome**

| Token | Hex | Notas |
|-------|-----|-------|
| `appBackground` | `#0E1119` | Negro con tinte azul, en línea con `#EDF2FA` |
| `appMenu` | `#0F1740` | Navy similar al claro, sigue siendo distinguible |
| `appTitle` | `#EDF2FA` | Invierte con el fondo claro |
| `appInfo` | `#9CA0AC` | Gris un poco más claro para mejor lectura en dark |
| `appDivider` | `#2A2E3A` | Separador sutil sobre fondo oscuro |

**Acento dinámico (por curso + tema)**

| Token | Origen | Uso |
|-------|--------|-----|
| `courseAccentLight` | Color dominante de la portada, **oscurecido ~20%** | Botón CTA en modo claro |
| `courseAccentDark` | Color dominante de la portada, **aclarado ~20%** | Botón CTA en modo oscuro |

Implementación: `UIColor(dynamicProvider:)` que devuelve la variante según
`traitCollection.userInterfaceStyle`. Si la portada es muy clara/blanca y
no se puede extraer un color útil, **fallback al morado `#7B5BF2`** de la
paleta de marca.

**Nota sobre `#7B5BF2`:** no es el color del CTA (esa función la tiene el
acento dinámico). Se usa como acento secundario: chips de etiquetas
activas, focus states, o el fallback descrito arriba.

**Tipografía**

- Familia: **SF Pro Rounded** (Display para títulos grandes, Text para cuerpo).
- Títulos detail: **28–34 pt bold**.
- Títulos tarjetas: **17–20 pt semibold**.
- Cuerpo: **15–17 pt regular**.
- Captions: **12–13 pt regular**, color `appInfo`.

### 14.2 Flujo principal

```
┌──────────────┐    ┌──────────────────┐    ┌─────────────────────────┐
│  Biblioteca  │ ─▶ │  Detalle curso   │ ─▶ │  Visor (Video/PDF/HTML)│
│  (grid/list) │    │  hero+curriculum │    │                         │
└──────────────┘    └──────────────────┘    └─────────────────────────┘
       │                    │
       │ lupa               │ "marcar completo"
       ▼                    ▼
  ┌────────────┐      escribe sidecar
  │ Búsqueda   │
  └────────────┘
```

### 14.3 Pantalla de bienvenida (solo primer launch)

- Hero image full-width (mockup de la app).
- Título grande: "Tus cursos, donde vayas."
- Subtítulo: "Copia desde tu Mac y retoma donde quedaste."
- Botón primario grande: "Listo, ya tengo mis cursos".
- Link secundario: "¿Cómo copio mis cursos?" → mini-tutorial con 3 pasos
  (1. Prepara carpeta en Mac, 2. Conecta por WiFi o USB, 3. Listo).

### 14.4 Biblioteca (estilo catálogo de cursos)

- **Layout superior:**
  - Barra de búsqueda `.searchable`, persistente arriba.
  - Chips horizontales de etiquetas (los `tags` únicos de la biblioteca):
    "Todos", "python", "backend", "2026". Toca uno para filtrar.
  - Toggle de orden: recientes / A–Z / % avance.
- **Grid de cursos (default, 2 columnas en iPhone, 3–4 en iPad):**
  - Tarjeta con cover 16:9 arriba, esquinas redondeadas (12 pt).
  - Título (2 líneas, truncado).
  - Barra de progreso fina + texto "X de Y lecciones • Z%".
  - Si tiene último visto: badge pequeño "Continuar ▶" abajo a la derecha.
- **Empty state:** ilustración simple + "Aún no tienes cursos. Agrega desde
  tu Mac o por USB." + botón "Mostrar carpeta en Archivos".
- **Botón flotante "+":** menú con "Recibir por WiFi" y "Mostrar en Archivos".

### 14.5 Detalle del curso (estilo "course landing")

**Cabecera (hero):**
- Cover 16:9 full-width.
- Debajo: título grande bold, chips de etiquetas (categoría), duración total
  estimada (# lecciones + suma de duraciones de videos).
- Botón primario grande (color dinámico de la portada del curso, ver
  §14.1.1 — `courseAccentLight` en claro, `courseAccentDark` en oscuro):
  - Si hay último visto: "Continuar aprendiendo: <nombre de lección> ▶"
  - Si está en 0%: "Empezar curso ▶"
- Barra de progreso: "X de Y lecciones • Z% completado".
- Botón secundario de texto: "Marcar curso como completado".

**Tabs (estilo Udemy):**
- **Contenido** (default) | **Descripción** | **Archivos**

**Tab Contenido (curriculum):**
- Acordeón de módulos, todos expandidos por defecto.
- Cabecera de módulo: nombre + palomita si todas sus lecciones están completas.
- Cada lección:
  - **Video:** miniatura 16:9 (provista o auto-generada, ver §13) + título +
    duración "12:34" + palomita si completa. Highlight si es el último visto.
  - **PDF / HTML:** ícono de tipo + título + palomita si completa.
- Tap → abre el visor.

**Tab Descripción:**
- Texto largo con formato (markdown básico). Si el sidecar tiene
  `description` se muestra; si no, "Sin descripción."

**Tab Archivos:**
- Lista plana de todos los archivos del curso (sin agrupar por módulo),
  útil para encontrar uno específico.

**iPad:**
- Split view: hero + resumen a la izquierda (40%), currículum a la derecha (60%).

### 14.6 Visor de video (AVKit)

- **iPhone:** video full-width arriba, controles estándar, debajo espacio
  para título de la lección + tabs ("Acerca de" / "Recursos").
- **iPad:** video a la izquierda (60–70%), currículum a la derecha
  (mismo árbol de módulos, con highlight en la lección actual).
- Auto-guardado de posición cada 5s, al pausar y al cerrar.
- Botón "Marcar como visto" en la barra superior (también toast "Marcar
  como completado?" al llegar al 95%).
- PiP soportado en iPad.
- **AirPlay:** el botón de AirPlay aparece automáticamente en los controles
  estándar de `AVPlayer` (no requiere código extra). Requisitos:
  - `UIBackgroundModes = audio` en `Info.plist` (para que la reproducción
    continúe con la app en segundo plano mientras ves en la TV).
  - `allowsExternalPlayback = true` en el `AVPlayer` (default, explícito).
  - El archivo de video se queda en el iPad; solo el stream viaja por la red.
  - El progreso (`positionSeconds`) y el sidecar se siguen actualizando igual.
  - Si más adelante queremos un botón custom en lugar del del sistema,
    agregar un `AVRoutePickerView` (no MVP).

### 14.7 Visor de PDF (PDFKit)

- Scroll vertical continuo con miniaturas opcionales (toggle en la barra).
- Auto-guardado de página actual.
- Barra superior: nombre del archivo + "12 / 45" + "Marcar como visto".
- iPad: mismo patrón split (PDF a la izquierda, currículum a la derecha).

### 14.8 Visor de HTML (WKWebView)

- Renderiza el HTML local con acceso a archivos relativos (links a PDFs/videos
  en la misma carpeta funcionan).
- Scroll position guardada (px → "segundos virtuales" para homogeneidad).
- Barra superior: nombre del archivo + "Marcar como visto".
- iPad: split view idéntico al visor de video.

---

## 15. Pantallas — App macOS

### 1. Biblioteca local

- Lista de cursos encontrados en `~/Movies/CursosIpad/` (o ruta configurable — **⚠️ por decidir** ruta por defecto).
- Cada fila: portada, título, # de archivos, peso total, fecha de modificación.
- Botón "+" para "Importar curso" (abre `NSOpenPanel`).

### 2. Editor de curso

- Panel izquierdo: árbol de módulos e items (drag & drop para reordenar).
- Panel derecho: preview del item seleccionado (Quick Look o AVKit embebido).
  - Para videos, el preview incluye botón **"Fijar este frame como miniatura"**
    que exporta el frame actual como `<video>.jpg` junto al `.mp4`
    (ver §13.4).
- Barra superior: editar título, asignar portada (botón "Elegir imagen" + "Auto-detectar"), campo de **etiquetas** (chip input estilo Mail: escribir + Enter para agregar, ✕ para quitar), descripción (textarea opcional).
- Botones: "Quitar del curso", "Renombrar".
- Botón inferior: **"Enviar al iPad"** (abre sheet de transferencia).

### 3. Transferencia

- Sheet modal.
- Lista de dispositivos detectados (Bonjour): "iPad de SalaZ — 192.168.1.42".
- Selección del dispositivo.
- Selección de cursos a enviar (checkboxes, default = todos los modificados).
- Barra de progreso por curso + global.
- Manejo de conflictos: radio "Sobrescribir | Saltar si existe | Preguntar".

### 4. Ajustes

- Ruta por defecto de la biblioteca.
- Puerto / Bonjour name (avanzado, opcional).
- Tema: **Sistema / Claro / Oscuro** (default: Sistema).
- La app Mac hereda el comportamiento de macOS (cambia con el sistema o
  forzado en Preferencias del Sistema); el ajuste de tema aquí aplica
  también a la app iOS vía sincronización del archivo de settings
  (**⚠️ por decidir** si vale la pena sincronizar o cada app usa su
  propio toggle local).

---

## 16. Búsqueda y filtrado (iOS)

Tres modos que se combinan en una sola barra `.searchable`:

### 16.1 Búsqueda por nombre (rápida, sin índice)

- Filtra en vivo sobre el título del curso (case-insensitive).
- Sin índice, en memoria — basta con decenas o cientos de cursos.

### 16.2 Filtro por etiqueta

- Chips horizontales arriba de la biblioteca con los `tags` únicos de la
  biblioteca + "Todos". Toca un chip para filtrar.
- Búsqueda por nombre + filtro por etiqueta se combinan.

### 16.3 Búsqueda full-text en subtítulos y HTMLs

**Qué se indexa:**
- **Subtítulos:** archivos `.srt` y `.vtt` junto a cada video. Solo
  sidecar, **no embebidos** dentro del `.mp4`.
- **HTML:** archivos `.html` y `.htm` del curso. Texto plano extraído
  con `NSAttributedString(html:documentAttributes:)` (no ejecuta JS).

**Qué NO se indexa:**
- PDFs (queda fuera de alcance).
- Subtítulos embebidos en `.mp4`.
- Videos (no son texto).

**Tecnología: SQLite FTS5**

- Built-in en iOS (sin paquete externo).
- Índice vive en app sandbox: `Library/Application Support/cursosIpad-index/index.sqlite`.
- 100% local, nunca sale del dispositivo. Se borra al desinstalar la app.

**Esquema simplificado:**

```sql
CREATE VIRTUAL TABLE search_index USING fts5(
  course_id UNINDEXED,
  course_title UNINDEXED,
  lesson_path UNINDEXED,    -- ruta relativa al archivo (video o html)
  kind UNINDEXED,            -- 'subtitle' | 'html'
  start_seconds UNINDEXED,  -- solo subtítulos: segundo de inicio del cue
  text                       -- texto del cue o fragmento HTML
);
```

**Construcción del índice:**

- Indexador corre en `Task` en background.
- **Primera vez:** escaneo completo de todos los cursos. Silencioso, no
  bloquea la UI. Puede tardar minutos en bibliotecas grandes — el usuario
  puede usar la app mientras se indexa.
- **Incremental:** detecta archivos nuevos / modificados / borrados por
  `mtime` y solo re-indexa esos.
- **Cancellable:** se cancela al ir a background, retoma al volver.

**UX de resultados:**

La misma barra `.searchable` muestra tres secciones (si hay matches):

1. **Cursos** — cursos cuyo título contiene el texto.
2. **Subtítulos** — hasta 5 resultados por curso, ordenados por relevancia
   FTS5. Cada uno: cover del curso + nombre de la lección + **snippet** de
   ~120 caracteres con la palabra resaltada + timestamp "min 12:34".
3. **HTMLs** — igual que subtítulos, pero con "párrafo N" en lugar de
   timestamp.

Tap en resultado de subs/HTML → abre el visor en esa posición exacta.

**Privacidad:**

- Índice 100% local, sin telemetría, sin red.
- Vive en app sandbox. Se borra al desinstalar la app.
- Si el usuario quiere "desindexar", un toggle en Ajustes puede borrar el
  índice (y deshabilitar la búsqueda full-text). **No MVP — opcional.**

---

## 17. Progreso — "recordar dónde voy"

### Por archivo

| Tipo | Cómo se mide | Cómo se guarda |
|------|--------------|----------------|
| Video | Segundos (`AVPlayer.currentTime()`) | Cada 5s, al pausar y al cerrar el visor |
| PDF | Número de página visible | Cada cambio de página y al cerrar |
| HTML | Posición de scroll (px) → convertido a "segundos virtuales" para homogeneidad | Al cerrar y cada 30s |

### Global del curso

- Porcentaje = `itemsCompletos / itemsTotales`.
- El completado lo marca el usuario con un botón. Al llegar al 95% de un video
  se muestra un toast "Marcar como completado?" como ayuda, **⚠️ por decidir**
  si en MVP se auto-completa al ver el 95% o solo se sugiere.

### "Continuar aprendiendo"

- En la cabecera del detalle del curso, si hay un item con `lastViewedAt`
  reciente, el botón primario grande dice
  "Continuar aprendiendo: <nombre de la lección> ▶" y abre ese item directo.
- Si el curso está en 0%, el botón dice "Empezar curso ▶" y abre la primera
  lección.
- En la biblioteca, las tarjetas con último visto muestran un micro-badge
  "Continuar ▶" abajo a la derecha.

---

## 18. Plan de implementación por fases

Cada fase termina con algo funcional. La idea es no pasar a la siguiente hasta
que la anterior se sienta **100% verde** (todos los checks marcados).

**Cómo usar este plan:**

- Cada `- [ ]` se marca como `- [x]` al completar el ítem.
- Cada fase tiene un **Entregable**: lo que debe estar funcionando (verificable
  en pantalla o por comando) al cerrar la fase.
- Antes de empezar una fase, todos los checks de la anterior deben estar
  marcados.
- Si un check es ambiguo al terminar, no se marca — se desglosa primero.
- Si aparecen bloques nuevos durante una fase, se agregan como checks dentro
  de la misma fase (no se brincan).

**Nota sobre la numeración:** los entregables referencian números de fase
antiguos cuando vienen del diseño previo. La fase "Detalle del curso" se
insertó como Fase 3 al detectar que faltaba cubrirla explícitamente.

---

### Fase 0 — Andamiaje (½ día)

**Checklist:**

- [x] Crear proyecto Xcode `CursosIpad.xcodeproj` con:
  - [x] Target iOS app (`CursosIpad`)
  - [x] Target macOS app (`CursosIpadMac`)
  - [x] Local Swift Package `Shared` (modelos compartidos)
- [x] Configurar `Info.plist` iOS:
  - [x] `UIFileSharingEnabled = YES`
  - [x] `LSSupportsOpeningDocumentsInPlace = YES`
  - [x] `NSLocalNetworkUsageDescription`
  - [x] `NSBonjourServices` con `_cursosipad._tcp`
  - [x] `UIBackgroundModes` incluye `audio`
- [x] Configurar `Info.plist` macOS (Bonjour + local network)
- [x] App iOS arranca en simulador con pantalla vacía
- [x] App macOS arranca con pantalla vacía
- [x] `.gitignore` (excluir `xcuserdata`, `DerivedData`, `.build`, `.swiftpm`)
- [x] `README.md` inicial con instrucciones de build (sideload con Xcode)

**Entregable:** proyecto que compila y abre "Hola mundo" en iOS y macOS.

---

### Fase 1 — Indexador de cursos (iOS) (1 día)

**Checklist:**

- [x] Modelos en `Shared/Sources/Shared/Models/`:
  - [x] `Course.swift` (id, folderName, title, coverFileName, tags, modules, totalProgress)
  - [x] `Module.swift` (id, folderName, title, items)
  - [x] `CourseItem.swift` (id, relativePath, type, title, sizeBytes, durationSeconds, progress)
  - [x] `ItemType` enum (`.video`, `.pdf`, `.html`)
  - [x] `ItemProgress.swift` (lastViewedAt, positionSeconds, lastPage, isCompleted, completionMarkedAt)
- [x] `CourseIndexer` en iOS:
  - [x] Escanea `Documents/` recursivamente (cada carpeta de primer nivel = un curso; ver §9 y §19)
  - [x] Detecta módulos = subcarpetas de primer nivel
  - [x] Detecta tipo por extensión (.mp4/.mov/.m4v/.webm/.pdf/.html/.htm)
  - [x] Detecta cover.jpg/cover.png/primera imagen en raíz
  - [x] Calcula sizeBytes y durationSeconds (video, con AVAsset)
  - [x] Devuelve `[Course]` ordenado por nombre
- [x] Pantalla de debug en iOS que muestra la lista cruda de cursos

**Entregable:** abrir la app y ver los nombres de las carpetas de cursos en `Documents/`.

---

### Fase 2 — Biblioteca iOS (1–2 días)

**Checklist:**

- [x] `LibraryView` con grid (2 columnas iPhone, 3–4 iPad)
- [x] Tarjeta de curso:
  - [x] Cover 16:9 con esquinas redondeadas 12 pt (placeholder si no hay)
  - [x] Título (2 líneas, truncado)
  - [x] Barra de progreso fina
  - [x] Texto "X de Y lecciones • Z%"
  - [x] Micro-badge "Continuar ▶" si tiene último visto
- [x] Chips horizontales de tags (scroll horizontal, "Todos" + únicos)
- [x] Barra `.searchable` con búsqueda por nombre (case-insensitive, en memoria)
- [x] Menú de orden (recientes / A–Z / % avance)
- [x] Toggle grid/lista
- [x] Empty state con copy en español ("Aún no tienes cursos. Agrega desde tu Mac o por USB.")
- [x] Botón flotante "+" con menú (Recibir por WiFi / Mostrar en Archivos)
- [x] iPad: `NavigationSplitView` con biblioteca a la izquierda
- [x] Tokens `Color` de la paleta SPID (ver §14.1.1) implementados como extensión
- [x] Extracción de color dominante de cover (para CTA dinámico)

**Entregable:** biblioteca bonita que lista cursos reales con grid, búsqueda, filtros y toggle de tema.

---

### Fase 3 — Detalle del curso (1 día)

**Checklist:**

- [ ] `CourseDetailView` con hero (cover 16:9 + título + tags + duración estimada)
- [ ] Botón CTA primario dinámico (color de portada, ver §14.1.1):
  - [ ] "Continuar aprendiendo: <última lección> ▶" si hay último visto
  - [ ] "Empezar curso ▶" si está en 0%
  - [ ] "Continuar viendo" si hay progreso pero no último visto
- [ ] Barra de progreso "X de Y lecciones • Z%"
- [ ] Botón secundario "Marcar curso como completado"
- [ ] Tabs (estilo Udemy): Contenido / Descripción / Archivos
- [ ] Tab Contenido (currículum):
  - [ ] Acordeón de módulos, expandidos por defecto
  - [ ] Cabecera de módulo con palomita si todas las lecciones completas
  - [ ] Video → miniatura 16:9 mini + duración + palomita + highlight si último visto
  - [ ] PDF/HTML → ícono de tipo + título + palomita
  - [ ] Tap → abre el visor
- [ ] Tab Descripción (markdown básico, fallback "Sin descripción")
- [ ] Tab Archivos (lista plana de todos los archivos del curso)
- [ ] iPad: split view (hero+resumen 40%, currículum 60%)
- [ ] Pantalla de bienvenida (primer launch): hero + tutorial 3 pasos

**Entregable:** abrir un curso muestra hero, tabs y currículum navegable; tap en lección abre visor.

---

### Fase 4 — Búsqueda full-text en subtítulos y HTMLs (1–2 días)

**Checklist:**

- [x] SQLite FTS5 setup en `Library/Application Support/cursosIpad-index/index.sqlite`
- [x] `SubtitleIndexer`:
  - [x] Parsea `.srt` con regex de timestamps → cues (start_seconds, text)
  - [x] Parsea `.vtt` con regex de timestamps → cues
- [x] `HtmlIndexer`:
  - [x] Extrae texto plano (pre-procesado regex puro, no `NSAttributedString` — esa API colapsaba el whitespace y destruía la estructura de párrafos; pre-procesar con regex y luego split por `\n\n+` conserva los límites de bloque)
  - [x] Genera bloques con texto + posición
- [x] `SearchIndexer` orquestador:
  - [x] Corre en `Task` en background
  - [x] **Indexación incremental** por `mtime` (solo archivos nuevos/modificados)
  - [x] Cancellable al ir a background, retoma al volver
- [x] UI de búsqueda extendida (en la misma `.searchable`):
  - [x] Sección "Cursos" (filtro por nombre)
  - [x] Sección "Subtítulos" con snippet + timestamp "min 12:34"
  - [x] Sección "HTMLs" con snippet + "párrafo N"
  - [x] Resaltar match en snippet
- [x] Tap en resultado:
  - [x] Subs → abre curso + lección + banner "min 12:34 — Reproductor llega en Fase 6"
  - [x] HTML → abre curso + lección + banner "párrafo N — Visor HTML llega en Fase 8"
- [x] Resultados se actualizan mientras el indexador corre

**Notas de implementación (desviaciones del plan original):**

- El plan proponía `NSAttributedString(html:documentAttributes:)` para extraer texto de HTML. En la práctica esa API destruye la estructura de párrafos (colapsa whitespace) y además requiere main thread, lo que obliga a `MainActor.run` y agrega latencia. Se reemplazó por pre-procesado con `NSRegularExpression` que reemplaza cierres de bloque (`</p>`, `<br>`, etc.) por `\n\n`, quita tags y entidades, y divide por `\n\n+` para obtener los párrafos. Más rápido y fuera del main thread.
- En lugar de `course_id UUID` en la tabla FTS5 se usa `course_key` (folder name) porque el `Course.id` se regenera en cada `refresh()` (los IDs estables llegan con el sidecar en Fase 5). Documentado en `SearchIndexDatabase.swift`.

**Entregable:** buscar "decorador" muestra resultados de subtítulos con snippet + timestamp; tap → navega al curso con la lección resaltada y un banner con la posición pretendida (el reproductor real llega en Fase 6, el visor HTML en Fase 8).

---

### Fase 5 — Sidecar + progreso (1 día)

**Checklist:**

- [x] Modelo `Sidecar` en `Shared`:
  - [x] `Sidecar.swift` con Codable
  - [x] Schema v1: `version, courseId, title, coverFileName, description, tags, items`
- [x] `SidecarStore`:
  - [x] Lee `.cursosIpad.json` de la carpeta del curso
  - [x] Escribe atómicamente (`Data.write(.atomic)` — tmp + rename en un syscall)
  - [x] Crea sidecar vacío si no existe (en `seedMissingSidecars`, post-step de `index()`)
  - [x] Si un item del sidecar no existe en disco, lo ignora (`apply` + `snapshot` lo podan)
- [x] Integración en `CourseIndexer`: carga sidecar y merge con items (`buildCourse` aplica id+progress; `seedMissingSidecars` siembra cursos nuevos)
- [x] Barra de progreso en biblioteca y detalle muestran datos reales del sidecar (verificado en simulador con sidecar inyectado mostrando 75%)

**Entregable:** sidecars creados para todos los cursos detectados; barra de progreso refleja datos reales.

**Notas de implementación (desviaciones del plan original):**

- `Course.id` pasa de `let` a `var` — el único callsite que lo muta es `SidecarStore.apply` cuando reescribe el UUID desde el sidecar. Docstring en `Course.swift` lo explica.
- `SidecarStore.apply` **solo consume `courseId` y progress por item** del sidecar. `title`/`coverFileName`/`description`/`tags` se mantienen filesystem-derived para que los renames en Finder fluyan naturalmente. El sidecar igual los semilla al primer indexado (para cuando llegue el editor Mac en Fase 10), pero iOS los ignora por ahora.
- Writes serializados por un actor privado `SidecarWriter` dentro de `SidecarStore.write` — pone las bases para que los writers per-item de Fase 6+ (video cada 5s, PDF al cambiar página, HTML cada 30s) no requieran re-trabajo de concurrencia.
- `.bak` en `read` cuando el decode falla: el archivo roto se mueve a `.cursosIpad.json.bak` y se siembra uno nuevo. Log de error + cero crash.
- ISO8601 en fechas vía `JSONEncoder.dateEncodingStrategy = .iso8601` (pinned en `SidecarStore`, no se filtra al `Codable` de `Course` que sigue usando default).
- Items huérfanos (relativePath borrado en disco) se podan automáticamente en cada write vía `snapshot(course:)`.

---

### Fase 6 — Reproductor de video (1 día)

**Checklist:**

- [x] `VideoPlayerView` con `AVPlayerViewController` (vía `VideoPlayerRepresentable`)
- [x] Reanudar en `positionSeconds` al abrir (eager seek, AVPlayer lo buffers si no está ready todavía)
- [x] Guardar progreso cada 5 segundos (vía `addPeriodicTimeObserver` en single-mechanism con pausa + MPNowPlayingInfoCenter + toast 95%)
- [x] Guardar progreso al pausar (mismo observer, check `timeControlStatus == .paused`)
- [x] Guardar progreso al cerrar (`tearDownPlayback` flusha + limpia `MPNowPlayingInfoCenter`)
- [x] Botón "Marcar como visto" en barra superior (llama `library.markItemCompleted`)
- [x] Toast "Marcar como completado?" al llegar al 95% (gate `toastFiredForThisItem`, reset en `.id(item.id)` swap)
- [x] Controles estándar (play/pause/scrub/velocidad — vienen incluidos en `AVPlayerViewController`)
- [x] PiP en iPad (configurado en `AVPlayerViewController`)
- [x] AirPlay (botón automático, `allowsExternalPlayback = true` en `AVPlayer`)
- [x] `ThumbnailGenerator`:
  - [x] Extrae frame al 25% con `AVAssetImageGenerator` (320×180, JPEG q=0.7)
  - [x] Cachea en `.thumbs/<safe-name>.jpg` con priority: `<video>.<img-ext>` provista > auto-generada
  - [x] Prioridad: provista (`<video>.jpg`) > auto-generada > placeholder
  - [x] Generación lazy en `Task.detached`, serializada por `ThumbnailQueue` actor (max 4 concurrentes)
- [x] iPad: split view (video a la izquierda, currículum a la derecha, mismo `HStack(spacing: 0)` + `Divider().background(Color.appDivider)`)

**Entregable:** abrir un curso → ir a su video → reanudar donde quedé, con miniaturas en currículum.

**Notas de implementación (desviaciones del plan original):**

- `UIViewControllerRepresentable` envuelve `AVPlayerViewController` (no SwiftUI `VideoPlayer` que es más opaco) — necesario para tener el `dismantleUIViewController` hook que limpia el `AVPlayer` viejo cuando `.id(item.id)` dispara un swap de lección.
- Single periodic time observer a 1Hz (no `Timer.publish` + KVO) — un solo mecanismo para flush + pausa + MPNowPlayingInfoCenter + toast 95%. Cleanup via `removeTimeObserver` en `tearDownPlayback`.
- `.id(item.id)` en `CourseDetailView.body` cuando hay lección seleccionada es CRÍTICO — sin él, swapear lección en el split iPad reusa la misma `AVPlayer` y sigue mostrando el video viejo. El `.id` fuerza reconstrucción completa del `VideoPlayerView` y `dismantleUIViewController` limpia el player viejo.
- Guard de writer en `didIssueInitialSeek && didReceiveFirstContentTime` — sin esto, un timer armado antes de que el seek inicial surta efecto escribiría `positionSeconds: 0` y borraría el punto de resume persistido. (Bug real identificado en la review del plan.)
- `updateItemProgress(courseID:relativePath:positionSeconds:lastViewedAt:isCompleted:completionMarkedAt:)` es field-keyed con defaults `nil` — evita la trampa de "olvidaste copiar `isCompleted`" que tendría una variante con closure `transform`.
- `markItemCompleted` queda como single entry point para el botón "Marcar como visto" manual **y** el futuro auto-complete de Fase 13; ambos llaman a la misma función.
- `MPNowPlayingInfoCenter` actualizado desde el periodic observer con `MPMediaItemPropertyTitle`, duración, posición, rate, y artwork (cover del curso via `library.coverURL(for:)`). Permite que Control Center / lock screen muestren el pill correcto durante AirPlay / background.
- `ThumbnailQueue` actor (`Shared` no, vive en `iOS/Player/`) con semaphore FIFO de máximo 4 generaciones concurrentes — evita que un scroll con 50 lecciones de video abra 50 `AVAsset`s a la vez.
- IPhone: el layout es stack (topbar + video + tabs "Acerca de/Recursos"). Currículum completo: out para iPhone (los visors de PDF/HTML son Fases 7/8).
- `ItemType.imageExtensions` reusado como single source of truth para las extensiones reconocidas como miniatura provista.
- `CurriculumLessonRow` usa `@State VideoThumbnailLoader` por lección. Inicializado lazy en `.task` con `@State` deferred (no en el init) para esperar al EnvironmentObject del padre. `.onDisappear` cancela la `Task`.
- Headless simulator (no hay Simulator.app GUI): la verificación visual completa del player requiere Simulator.app corriendo, lo cual no está disponible en este entorno. Build green + sidecars seeded + thumbnails-only-on-row-appear confirmados en simulador. La verificación end-to-end del player queda como pendiente para el usuario (instrucciones en sección "Out of scope").

---

### Fase 7 — Visor PDF (½ día)

**Checklist:**

- [x] `PDFViewerView` con `PDFKit.PDFView`
- [x] Reanudar en `lastPage` al abrir
- [x] Guardar página al cambiar
- [x] Guardar página al cerrar
- [x] Botón "Marcar como visto"
- [x] Toggle miniaturas de páginas
- [x] iPad: split view (PDF a la izquierda, currículum a la derecha)

**Entregable:** PDFs funcionan idéntico a videos (reanudar + completar + split iPad).

**Notas de implementación (desviaciones del plan original):**

- `UIViewRepresentable` envuelve `PDFView` directamente (no `UIViewControllerRepresentable` con un VC intermediario) — `PDFView` ya es la chrome, no necesita un VC encima. El hook de teardown es `dismantleUIView` (no `dismantleUIViewController` como en `VideoPlayerRepresentable`).
- El `Coordinator` es dueño del `PDFDocument` y del token del observer de `PDFViewPageChanged`. Esto ata el ciclo de vida del documento a la identidad de la representable, así un swap de lección (vía `.id(lesson.id)` en el padre) libera el documento viejo antes de montar el nuevo — sin esto, PDFs viejos quedarían retenidos en memoria.
- Suscripción al `PDFViewPageChanged` notification ocurre **después** del `go(to:)` inicial. Si suscribimos antes, la primera notificación sería el propio resume seek; después, la primera notificación es siempre un cambio genuino del usuario. El "resume-race gate" del video player (`didIssueInitialSeek && didReceiveFirstContentTime`) **no es necesario** aquí porque `PDFView.go(to:)` es sincrónico.
- `dismantleUIView` debe llamar `NotificationCenter.default.removeObserver(token)` y `uiView.document = nil`. Sin el removeObserver, cada swap de lección deja un observer zombie que apunta a un Coordinator muerto — el siguiente PDF no recibiría eventos de cambio de página.
- `.id(lesson.id)` en `CourseDetailView.body` vive **fuera** del `Group { switch }` que dispatcha por `lesson.type`. Esto fuerza reconstrucción completa en cada swap de lección (disparando `dismantleUIView`/`dismantleUIViewController` en el viewer viejo). Si el `.id` va dentro del switch, SwiftUI reusa la misma identidad entre lecciones del mismo tipo y el `PDFView` viejo no se desmonta.
- `LibraryStore.updateItemProgress` recibió `lastPage: Int? = nil` como **último** parámetro (signature-additive — no rompe los call sites del video player, que ya pasaba `positionSeconds`). El mutation block lo aplica a `item.progress.lastPage` con el mismo patrón `if let v = lastPage { ... }` que el resto de los campos.
- El `switch` de dispatch de lección se extrajo a una computed property `lessonView(course:lesson:)` en `CourseDetailView` porque el type-checker de SwiftUI no puede resolver inline un `switch` con argumentos no triviales en ViewBuilders — el "expresión demasiado compleja" típico que pega cuando un dispatch ViewBuilder crece a 3+ casos.
- **Bonus de UX no estaba en el checklist original:** un toggle de "pantalla completa" en la top bar que oculta la columna del currículum en iPad (el PDF toma el 100% del ancho) y la sección de "Acerca de/Recursos" en iPhone. Solicitado por el usuario durante la verificación.

---

### Fase 8 — Visor HTML (½ día)

**Checklist:**

- [x] `HTMLViewerView` con `WKWebView`
- [x] Carga `file://` con acceso a carpeta local (links relativos a PDFs/videos)
- [x] Detecta scroll position al cerrar (guarda como "segundos virtuales")
- [x] Botón "Marcar como visto"
- [x] iPad: split view (HTML a la izquierda, currículum a la derecha)

**Entregable:** HTMLs funcionan con links relativos y reanudar scroll.

**Notas de implementación (desviaciones del plan original):**

- `HTMLViewerRepresentable` envuelve `WKWebView` directamente (mismo patrón que `PDFViewerRepresentable` — un `UIViewRepresentable` sobre el SDK view, no un `UIViewControllerRepresentable`). El Coordinator es dueño del `WKWebView` y del token KVO de `scrollView.contentOffset`.
- `loadFileURL(_:allowingReadAccessTo: courseDir)` carga el HTML con acceso al directorio del curso, así los links relativos (`<a href="intro.html">`, `<img src="cover.png">`) resuelven correctamente. `decidePolicyFor` bloquea cualquier navegación que no sea `file://` dentro del directorio concedido — sin red, sin `mailto:`, sin iframes externos. Esto es sandboxing deliberado para contenido local.
- El "segundos virtuales" del plan §17 se implementan como `contentOffset.y / 100.0` (1s ≈ 100px ≈ una línea de texto default). El factor no es load-bearing — solo round-trip en disco; lo centralizamos en `HTMLViewerRepresentable.offset(from:)` para que cualquier ajuste futuro viva en un solo lugar.
- Restauración de scroll en `webView(_:didFinish:)` (no en `didStartProvisionalNavigation`): a `didFinish` el DOM está laid out y `scrollView.contentSize` ya está calculado, así `setContentOffset` funciona sin un hop a JS. Mismo hook usado por el jump a párrafo (`evaluateJavaScript` con un selector que cuenta block-level elements — `p,h1..h6,li,blockquote,pre,div,section,article,header,footer,main,aside`).
- **Resume-race gate simplificado:** un solo flag `hasIssuedInitialRestore` en el Coordinator (vs los dos flags del video player — `didIssueInitialSeek` + `didReceiveFirstContentTime`). HTML no tiene un equivalente a `AVPlayer.currentItem.status == .readyToPlay`, así que un gate es suficiente. Sin él, el primer KVO tick del scroll observer escribiría `positionSeconds: 0` y borraría el punto de resume persistido (mismo bug que en video, distinto trigger).
- Guard de "una sola vez" en el callback de consumo de posición (`didCallOnPositionConsumed`): si el `.id(item.id)` swap dispara el callback por accidente, no se vuelve a invocar — y un reopen del mismo curso no limpia el banner prematuramente.
- **Bonus de UX no estaba en el checklist:** toggle de pantalla completa en la top bar (espejo del bonus de Fase 7 para el visor PDF — iPad oculta la columna del currículum, iPhone oculta los tabs de "Acerca de/Recursos").
- **Bonus de UX:** flush cada 30s además del flush en `dismantleUIView` (plan §17 dice "on close y cada 30s"). Implementado con `Timer.publish(every: 30, on: .main, in: .common)` en el `body`; solo escribe si el representable reportó un offset nuevo desde el último flush (no churn cuando el usuario está inactivo).
- `SearchPositionBanner` ya no dice "El visor con scroll a párrafo llega en la Fase 8" — actualizado para mencionar el visor funcionando.
- `CourseDetailView.handleOpenLesson` ya no muestra la alerta "Próximamente" para HTML — ahora hace `selectedLesson = item` igual que video y PDF. La extensión `SearchPosition.paragraphIndexForHTML` se agregó como espejo de `startSecondsForVideo` para que el detail view pase un único `Int?` al visor sin importar la forma de la posición.
- Verificación end-to-end del visor (tap real en una lección HTML, scroll, link relativo, jump a párrafo) queda como pendiente para el usuario en simulador con GUI — el entorno actual no tiene Simulator.app corriendo ni herramientas de UI automation. Build green + indexer reconoció los 3 HTML del curso de prueba (FTS5 muestra los 14 bloques de `index.html` con paragraph_index correcto) + logs de launch sin errores de HTMLViewer/WKWebView + la API pública se probó indirectamente vía el path de `decidePolicyFor` y la serialización de KVO.

---

### Fase 9 — Biblioteca macOS + importador (1 día)

**Checklist:**

- [x] `LibraryView` macOS lista carpetas de cursos en `~/Movies/CursosIpad/` (configurable)
- [x] `NSOpenPanel` para importar curso (arrastrar o abrir)
- [x] Editar título del curso
- [x] Editar portada (auto-detectar o elegir imagen)
- [x] Editar descripción (textarea opcional)

**Entregable:** la app Mac ve y modifica cursos en su biblioteca.

**Notas de implementación (desviaciones del plan original):**

- `iOS/Library/SidecarStore.swift` se movió a `Shared/Sources/Shared/Sidecar/SidecarStore.swift`. Era Foundation-only desde el inicio (`URL`/`FileManager`/`JSONEncoder`), así que la mudanza lo hace accesible desde macOS sin duplicación — el Mac editor (Fase 9) persiste los mismos `.cursosIpad.json` que la app iOS lee en su primer index. Plan §19 todavía tiene `⚠️ por decidir` sobre la "ruta por defecto en Mac", resuelto aquí: `~/Movies/CursosIpad/` (almacenada en `UserDefaults`).
- El editor Mac escribe `title`/`description`/`coverFileName` al sidecar, pero iOS `SidecarStore.apply()` sigue consumiendo solo `courseId` + progress por ítem (contrato de Fase 5). El `apply()` se ampliará en Fase 10 según el plan, no en Fase 9 — la justificación es que sin transferencia (Fase 11) la inconsistencia es invisible y abre Fase 10 con un solo diff enfocado.
- `MacCourseIndexer` corre sin pasada de `AVAsset` (a diferencia de iOS) porque el editor Mac no muestra duraciones en ningún lado de Fase 9; las duraciones se calculan on-demand en Fase 10 cuando el preview de video las necesite.
- `Color.appBackground`/etc. para macOS se implementan con `NSColor(name:dynamicProvider:)` — el equivalente UIKit de `UIColor(dynamicProvider:)` no existe, así que cada token macOS es su propio provider. `Color.themeAdjusted(from:)` para macOS usa `NSColor.getHue` (que devuelve `Void` en AppKit — distinto de `UIColor` que devuelve `Bool`).
- `MacCourseOperations` aísla toda la lógica de `NSOpenPanel`/filesystem fuera de las views para que las views queden declarativas y las operaciones sean independientemente testeables.
- El Mac app no incluye un flag `hasSeenWelcome` como iOS: la `WindowGroup` siempre muestra la biblioteca, y si está vacía se renderiza `MacWelcomeView` con los botones Importar / Elegir carpeta. No hay carrusel de onboarding que descartar.

---

### Fase 10 — Editor de curso (Mac) (1–2 días)

**Checklist:**

- [x] Drag & drop para reordenar módulos e items
- [x] Renombrar archivos y módulos
- [x] Eliminar archivos no deseados
- [x] Auto-detección de portada mejorada
- [x] Campo de etiquetas (chip input estilo Mail)
- [x] "Fijar este frame como miniatura" desde preview de video:
  - [x] Botón en el panel de preview
  - [x] Scrubea el video
  - [x] Exporta el frame como `<video>.jpg` junto al `.mp4`

**Entregable:** editor usable + herramienta para fijar miniaturas.

**Notas de implementación (desviaciones del plan original):**

- `Course` ahora carga `description: String?` para que el editor Mac pueda leer el valor del sidecar a través de la `Course` en vez de `SidecarStore.read` directo (consistencia con `title`/`coverFileName`/`tags`). `SidecarStore.apply()` se ensanchó para consumir `description` y `tags` (cierra la deuda que la nota de cierre de Fase 9 dejó explícita). `snapshot()` propaga `description` — sin esto, el primer write de progreso del iOS borraría la descripción que el Mac acaba de escribir.
- Como side effect del ensanche de `apply()`, los chips de tags de la biblioteca iOS (`iOS/Views/Library/LibraryView.swift:366`) y el filtro por etiqueta empiezan a funcionar en cuanto un curso tenga tags en su sidecar. La pestaña "Descripción" del iOS (`iOS/Views/Detail/CourseDescriptionView.swift`) ahora muestra el texto escrito en Mac — verificado con un cambio de 5 líneas en `CourseDetailView.swift:316`.
- `MacCourseOutline` usa SwiftUI's `.draggable` + `.dropDestination` con un `Transferable` privado (`OutlineTransfer`) para los drops entre módulos, y `.onMove` para reordenar intra-módulo. Reordenar persiste renombrando con prefijo numérico (`01-`, `02-`, …) — el indexer ordena por `localizedStandardCompare`, así que el filesystem es la fuente de verdad. Colisiones se resuelven subiendo el prefijo (`02, 03, 04…`); el usuario puede limpiar manualmente si quiere una secuencia estricta.
- Borrado via `FileManager.trashItem` (recuperable desde la Papelera). El sidecar se limpia de las entradas huérfanas en el próximo `snapshot(course:)`.
- Rename muestra un alert de "se perderá el progreso" antes de confirmar (per contrato Fase 5 en `Sidecar.swift:29-32`). Copy distinto para módulo (afecta N lecciones) vs ítem (1).
- `MacVideoThumbnailExtractor` mirror del iOS `ThumbnailGenerator` pero sin UIKit (usa `CGImage` directo + `CGImageDestination`). Reusado por el botón "Fijar este frame" y por `autoDetectCoverImproved`.
- "Fijar este frame" usa `VideoPlayer` de SwiftUI (macOS 14+) en vez de envolver `AVPlayerView` con `NSViewRepresentable`. Un `TimelineView(.periodic(by: 0.25))` samplea `timeControlStatus` para deshabilitar el botón cuando el video no está en pausa. Atajo ⌘F. Escribe a `<video>.jpg` junto al `.mp4` — el iOS app lo recoge como miniatura provista (prioridad 1 en §13.1) en el próximo index.
- `autoDetectCoverImproved` mantiene la prioridad existente (`cover.jpg` → `cover.png` → primera imagen en raíz) y agrega un fallback: si no hay imágenes, extrae un frame del primer video del curso a 25% de duración y lo guarda como `cover.jpg`. No promueve `<video>.jpg` siblings a portada — la regla de §13.1 es que esos son thumbnails por-lección, no candidatos a cover.
- ⚠️ El botón "Enviar al iPad" del bottom bar es un placeholder disabled (Fase 11).
- ⚠️ Drag & drop de carpetas desde Finder hacia la app no se implementó (Fase 9 original mencionaba "arrastrar o abrir" pero el implementador optó por NSOpenPanel solamente; queda como follow-up).
- ⚠️ No hay test target; la verificación es smoke test manual según la matriz de §Fase 10 del plan.

---

### Fase 11 — Transferencia por WiFi (1–2 días)

**Checklist:**

- [ ] iOS: `NWListener` + Bonjour advertise `_cursosipad._tcp`
- [ ] iOS: servidor HTTP (⚠️ Swifter vs NWListener custom)
  - [ ] `GET /api/ping` → devuelve versión
  - [ ] `POST /api/courses` con multipart (metadata JSON + ZIP)
- [ ] iOS: descomprime ZIP en `Documents/<nombre>/` (⚠️ ZIPFoundation)
- [ ] iOS: actualiza indexador al terminar transferencia
- [ ] macOS: `NWBrowser` descubre servicios `_cursosipad._tcp`
- [ ] macOS: UI muestra dispositivos detectados (Bonjour)
- [ ] macOS: cliente `URLSession` con multipart + progreso
- [ ] macOS: empaqueta curso (ZIP) con ZIPFoundation
- [ ] macOS: manejo de conflictos (sobrescribir / saltar)
- [ ] macOS: barra de progreso por curso + global + velocidad

**Entregable:** enviar un curso desde la Mac al iPad por WiFi y que aparezca en la biblioteca.

---

### Fase 12 — Detección por USB (½ día)

**Checklist:**

- [ ] Indexador iOS corre al abrir la app (no solo primer launch)
- [ ] Re-escaneo automático al detectar cambios en `Documents/`
- [ ] Verificar que arrastrar carpetas en Finder → iPad → app funciona
- [ ] Verificar que la app Archivos ve los cursos (file sharing habilitado)

**Entregable:** transferencia por USB funcional.

---

### Fase 13 — Pulido (1–2 días)

**Checklist:**

- [ ] Conflictos en transferencia (UI de sobrescribir / saltar)
- [ ] Empty states con copy en español en todas las pantallas
- [ ] Icono y pantalla de inicio (LaunchScreen)
- [ ] **Tema claro/oscuro:**
  - [ ] Toggle en Ajustes funciona (Sistema / Claro / Oscuro)
  - [ ] Accent color dinámico legible en ambos
  - [ ] Status bar y navigation bar se ajustan
  - [ ] Sin hardcoded colors fuera de los tokens
- [ ] **Paleta SPID (chrome):**
  - [ ] Tokens `appBackground`, `appMenu`, `appTitle`, `appInfo`, `appDivider` consistentes
  - [ ] CTA dinámico usa variante correcta por tema
  - [ ] Fallback al morado `#7B5BF2` funciona
- [ ] Deep link al último archivo visto del curso (URL scheme / push notification)
- [ ] Pruebas con 3–4 cursos reales de distintos tamaños
- [ ] Pruebas en ambos temas
- [ ] `README.md` final con instrucciones de uso (en español)

**Entregable:** app presentable para uso diario.

---

### Total estimado

~14–17 días de trabajo tranquilo (no full-time).

### Trazabilidad MVP → fases

Para confirmar que nada del §4 (Alcance MVP) quedó sin cubrir:

| MVP | Fase(s) |
|-----|---------|
| Bienvenida + selector | Fase 3 (pantalla de bienvenida) |
| Biblioteca estilo Udemy | Fase 2 |
| Chips de tags | Fase 2 |
| Búsqueda por nombre | Fase 2 |
| Orden de biblioteca | Fase 2 |
| Búsqueda full-text | Fase 4 |
| Detalle del curso + tabs | Fase 3 |
| Currículum con palomitas | Fase 3 |
| Extracción color portada | Fase 2 |
| Paleta SPID | Fase 2 (tokens), Fase 13 (validación) |
| iPad NavigationSplitView | Fase 2 (biblioteca), Fase 3 (detalle split), Fases 6/7/8 (visor split) |
| Reproductor de video | Fase 6 |
| AirPlay | Fase 6 |
| Miniaturas | Fase 6 |
| Visor PDF | Fase 7 |
| Visor HTML | Fase 8 |
| Persistencia sidecar | Fase 5 |
| Detección USB | Fase 12 |
| Tema claro/oscuro | Fase 13 |
| Deep link | Fase 13 |
| App macOS biblioteca | Fase 9 |
| App macOS editor | Fase 10 |
| App macOS tags | Fase 10 |
| App macOS "fijar frame" | Fase 10 |
| Bonjour / transferencia WiFi | Fase 11 |
| Conflictos transferencia | Fase 11 (UI), Fase 13 (refinamiento) |
| Estructura carpetas (común) | Fase 1 |
| Sidecar (común) | Fase 5 |
| Detección tipo por extensión | Fase 1 |

---

## 19. Riesgos y decisiones pendientes

| # | Tema | Pregunta | Impacto si se decide tarde |
|---|------|----------|---------------------------|
| ⚠️ 1 | Servidor HTTP en iOS | ¿Usar **Swifter** (dependencia) o escribir uno propio con `NWListener`? | Bajo — se puede cambiar después sin tocar UI. |
| ⚠️ 2 | Empaquetado para transferencia | ¿Enviar **ZIP** o **archivo por archivo**? | Medio — afecta performance y atomicidad. |
| ⚠️ 3 | Auto-completar al final del video | ¿Se completa solo al ver el 95% o solo se sugiere con toast? | Bajo — solo UX. |
| ⚠️ 4 | Conflicto "fusionar" | ¿Manejar fusiones de cursos o siempre sobrescribir/saltar? | Bajo — se puede dejar fuera del MVP. |
| ⚠️ 5 | Ruta por defecto en Mac | ¿`~/Movies/CursosIpad/` o preguntar siempre? | Nulo. |
| ⚠️ 6 | Módulo virtual "General" | ¿Archivos sueltos en la raíz forman módulo o se ocultan? | Bajo — UX. |
| ⚠️ 7 | Color de acento | ¿Extraer color dominante de la portada (`UIImage`) o usar color fijo? | Bajo — UX. |

### Decisiones cerradas (referencia)

Esta sección documenta decisiones que empezaron como ⚠️ y se resolvieron, para
que el contrato quede escrito en un solo lugar y no se reabra la conversación.

- **Ruta raíz de cursos en iOS** (resuelta al implementar la transferencia
  USB Finder, 2026-10-09): `Documents/Cursos/` → **`Documents/`** directo.
  Motivo: lo que aparece en Finder/Archivos bajo `cursosIpad` ES la raíz de
  `Documents/`; pedirle al usuario crear una subcarpeta `Cursos/` adentro
  rompe el flujo natural de "arrastro el curso y listo". La constante
  `CourseIndexer.Configuration.documentsSubdirectory` quedó como opt-in
  (default `""`) por si en el futuro se quiere volver a la jerarquía.
  Impacto en otros componentes: `LibraryStore.courseDirectoryURL(for:)`
  y `SearchIndexer.coursesRoot` también resolvieron al nuevo root.
  Implementación Fase 11 (servidor HTTP) debe descomprimir en
  `Documents/<nombre>/`, no en `Documents/Cursos/<nombre>/`.

---

## 20. Próximo paso

Revisar este plan contigo. Cualquier cosa que no coincida con lo que tienes en
mente, lo ajustamos antes de tocar código. Cuando esté firme:

1. Empezamos por la **Fase 0** (andamiaje del proyecto Xcode).
2. Vamos fase por fase, con demos al final de cada una.