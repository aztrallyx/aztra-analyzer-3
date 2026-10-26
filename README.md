# Aztra Analyzer 2.1

Analizador de calidad de audio para Android. Basado en el de Mornye
(https://github.com/mornyeapp/Mornye): `audio_analysis_ffmpeg.dart` y
`audio_analysis_models.dart` son los originales de Mornye, sin tocar su logica
(solo se agrego al final una variante para el analisis por carpetas que usa la
misma cadena de filtros del corte espectral).

## Que hace
- Analiza canciones sueltas o carpetas completas (con subcarpetas).
- Sigue analizando en segundo plano SOLO mientras analiza, con una
  notificacion de progreso. Al terminar, el servicio se apaga solo.
- Guarda solo los numeros de cada cancion (unos 2 KB por cancion).
- Espectrograma al abrir una cancion, con cache de tope configurable (64 MB).
- Comparar dos canciones (A vs B): resumen, tabla y los dos espectrogramas.
- Buscar duplicados: idénticos y "probables" (por duracion y niveles).
- Ordenar, buscar, filtros "Sospechosas" y "Comprimidas", exportar CSV.
- Fuente de Mornye (Google Sans Flex), Inter, la del sistema o la tuya (.ttf/.otf).

## Compilar (GitHub Actions)
1. Sube `aztra_analyzer.zip` (sin descomprimir) a la raiz del repo.
2. Sube `build.yml` a `.github/workflows/` (reemplaza el anterior).
3. Actions > Build APK > Run workflow.
4. El APK queda en la seccion Releases del repo.

## Licencia
LGPL-3.0 (ver LICENSE, COPYING y NOTICE). Fuentes Google Sans Flex e Inter bajo
SIL Open Font License (ver assets/licenses).
