# Aether Player

Reproductor de música multiplataforma hecho con **Flutter**. Permite buscar canciones, armar tu biblioteca y playlists, ver letras sincronizadas (karaoke) y reproducir audio/video, usando YouTube/YouTube Music como fuente de contenido.

## Características

- Búsqueda y exploración de música (YouTube Music).
- Descarga de audio para escuchar sin conexión.
- Biblioteca personal y gestor de playlists.
- Letras sincronizadas / modo karaoke.
- Reproductor con mini-player y vista completa, soporte de reproducción en segundo plano.
- Extracción de metadatos y carátulas (paleta de colores dinámica según el álbum).

## Tecnologías

- [Flutter](https://flutter.dev) / Dart
- `just_audio` + `just_audio_background` para la reproducción
- `youtube_explode_dart` y `dart_ytmusic_api` para obtener el contenido
- `sqflite` para almacenamiento local
- `provider` para el manejo de estado

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

## Aviso legal

Este proyecto es un ejercicio personal/educativo de desarrollo con Flutter. No está afiliado, respaldado ni patrocinado por YouTube, YouTube Music ni Google.

La descarga de contenido protegido por derechos de autor sin permiso puede infringir los [Términos de Servicio de YouTube](https://www.youtube.com/t/terms) y la legislación de propiedad intelectual aplicable en tu país. El uso de esta aplicación es responsabilidad exclusiva de quien la ejecuta; los autores no se hacen responsables del uso que se le dé.

## Licencia

Este proyecto se distribuye bajo la licencia [MIT](LICENSE).
