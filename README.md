# Aether Player

Reproductor de música multiplataforma hecho con **Flutter**. Permite buscar canciones, armar tu biblioteca y playlists, ver letras sincronizadas (karaoke) y reproducir audio/video, usando YouTube/YouTube Music como fuente de contenido.

## Características

- Búsqueda y exploración de música y videos (YouTube Music), con vista previa antes de descargar.
- Búsqueda de álbumes completos.
- Descarga de audio (MP3) y de video en varias calidades para ver/escuchar sin conexión.
- Biblioteca personal y gestor de playlists, con opción de ocultar o eliminar canciones.
- Letras sincronizadas / modo karaoke.
- Reproductor con mini-player (con barra de progreso) y vista completa, soporte de reproducción en segundo plano.
- Extracción de metadatos y carátulas (paleta de colores dinámica según el álbum), con actualización manual de portadas y datos de artista.
- Pestaña de Videos locales en la Biblioteca.

## Tecnologías

- [Flutter](https://flutter.dev) / Dart
- `just_audio` + `just_audio_background` para la reproducción
- `youtube_explode_dart` y `dart_ytmusic_api` para obtener el contenido
- `sqflite` para almacenamiento local
- `provider` para el manejo de estado
- `cached_network_image` para el caché de portadas/miniaturas

## Descargar

La APK para Android está disponible en la sección [**Releases**](../../releases) de este repositorio.

> No se distribuye la app compilada dentro del código fuente del repositorio para no inflar su tamaño; cada versión se publica como adjunto en un *Release*.

## Compilar desde el código fuente

Requiere tener el [SDK de Flutter](https://docs.flutter.dev/get-started/install) instalado.

```bash
git clone https://github.com/NekoCoder-en/Aehter.git
cd Aehter
flutter pub get
flutter run            # ejecutar en un dispositivo/emulador conectado
flutter build apk      # generar la APK de release
```

## Historial de versiones

### 1.1.0 (actual)
- **Explorar**: vista previa (audio) de canciones y videos antes de descargar; descarga de video con selector de calidad, además del audio en MP3; búsqueda de álbumes reactivada; feedback visual de error en descargas con reintento.
- **Biblioteca / Inicio**: eliminar una canción ahora la borra permanentemente (ya no queda en "ocultas"); "Actualizar portadas" también corrige artista/título vía YouTube Music; fix de miniaturas de video que se recargaban al volver de reproducir un video.
- **Reproductor**: rediseño de la hoja de opciones (accesos rápidos, fotos de artista más confiables) y barra de progreso en el mini-player.
- **General**: notificaciones propias (reemplazan los avisos por defecto), caché de imágenes de red y menor consumo al descargar en segundo plano.

### 1.0.0
- Versión inicial: búsqueda y reproducción de música vía YouTube Music, descarga de audio, biblioteca y playlists, letras sincronizadas / karaoke, mini-player y reproductor completo.

## Reportar un problema o sugerir algo

Los issues de este repositorio se organizan con estas etiquetas:

| Etiqueta | Significado |
|---|---|
| `bug` | Algo no está funcionando |
| `documentation` | Mejoras o agregados a la documentación |
| `duplicate` | Este issue o pull request ya existe |
| `enhancement` | Una funcionalidad o pedido nuevo |
| `good first issue` | Buen punto de entrada para nuevos colaboradores |
| `help wanted` | Se necesita una mano extra |
| `invalid` | Esto no parece correcto |
| `question` | Se necesita más información |
| `wontfix` | No se va a resolver |

## Aviso legal

Este proyecto es un ejercicio personal/educativo de desarrollo con Flutter. No está afiliado, respaldado ni patrocinado por YouTube, YouTube Music ni Google.

La descarga de contenido protegido por derechos de autor sin permiso puede infringir los [Términos de Servicio de YouTube](https://www.youtube.com/t/terms) y la legislación de propiedad intelectual aplicable en tu país. El uso de esta aplicación es responsabilidad exclusiva de quien la ejecuta; los autores no se hacen responsables del uso que se le dé.

## Licencia

Este proyecto se distribuye bajo la licencia [MIT](LICENSE).
