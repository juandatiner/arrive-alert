# Arrive Alert

Avisa a tiempo de bajarte del bus, colectivo o taxi. Elige tu destino en el
mapa, arranca el viaje, y la app vigila tu ubicacion en segundo plano para
sonar una alarma antes de que te pases la parada.

<p align="center">
  <img src="assets/icon/app_icon.png" width="120" alt="Icono de Arrive Alert" />
</p>

## Que hace

- **Elige destino en el mapa** — busca una direccion, toca el mapa, o reusa
  un lugar reciente/favorito.
- **Ruta y tiempo estimado** — calculados con [OSRM](http://project-osrm.org/)
  sobre la red vial real, con un margen extra para tráfico urbano.
- **Avisos escalonados** — primer aviso, segundo aviso (opcional) y alarma
  final, cada uno con su propio umbral en minutos configurable.
- **Alarma dificil de ignorar** — sonido en loop, vibracion y notificacion a
  pantalla completa; sigue sonando con la pantalla apagada o la app en
  segundo plano.
- **Funciona con permisos parciales** — si el usuario niega ubicacion,
  notificaciones, o solo da "mientras se usa", la app explica que falta y
  ofrece el boton correcto (reintentar o abrir ajustes) en vez de quedar
  atascada.

## Capturas

| Mapa | Viaje en curso | Ajustes |
|---|---|---|
| _(agrega captura)_ | _(agrega captura)_ | _(agrega captura)_ |

## Stack tecnico

| Área | Paquete/servicio |
|---|---|
| UI / mapa | [`flutter_map`](https://pub.dev/packages/flutter_map) + tiles OpenStreetMap |
| Ubicacion | [`geolocator`](https://pub.dev/packages/geolocator) |
| Permisos | [`permission_handler`](https://pub.dev/packages/permission_handler) |
| Notificaciones | [`flutter_local_notifications`](https://pub.dev/packages/flutter_local_notifications) |
| Geocodificacion | [Nominatim](https://nominatim.org/) (OpenStreetMap) |
| Ruteo | [OSRM](http://project-osrm.org/) (`router.project-osrm.org`) |
| Alarma | [`audioplayers`](https://pub.dev/packages/audioplayers) + [`vibration`](https://pub.dev/packages/vibration) |
| Persistencia local | [`shared_preferences`](https://pub.dev/packages/shared_preferences) |
| Icono / splash | [`flutter_launcher_icons`](https://pub.dev/packages/flutter_launcher_icons) + [`flutter_native_splash`](https://pub.dev/packages/flutter_native_splash) |

Ver la [wiki](../../wiki) para el detalle de arquitectura, por que cada
decision se tomo, y como regenerar el icono.

## Empezar

```bash
flutter pub get
flutter run                 # dispositivo o emulador conectado
```

Requiere Flutter con Dart SDK `^3.12.2` (ver `pubspec.yaml`). No hace falta
ninguna API key: mapa, geocodificacion y ruteo usan servicios publicos y
gratuitos de OpenStreetMap.

### Compilar para instalar (release)

```bash
flutter run --release -d <device-id>   # iOS: sobrevive sin el debugger conectado
flutter build apk                       # Android
flutter build ios                       # iOS (requiere firma en Xcode)
```

`flutter devices` lista los dispositivos/emuladores disponibles.

## Estructura del proyecto

```
lib/
  main.dart                 # entrypoint, tema, init de notificaciones
  models/                   # Place, AlertSettings, RouteInfo
  screens/
    home_screen.dart        # mapa + busqueda + favoritos/recientes
    confirm_trip_screen.dart
    trip_screen.dart        # seguimiento en vivo + alarma
    settings_screen.dart    # umbrales de aviso, sonido/vibracion
  services/
    location_service.dart   # ciclo de permisos de ubicacion
    notification_service.dart
    alert_service.dart      # dispara avisos segun umbral
    alarm_player.dart
    geocoding_service.dart  # Nominatim
    routing_service.dart    # OSRM + heuristica de trafico urbano
    places_history_service.dart
  widgets/
    map_style.dart          # tile layer + atribucion compartidos
assets/
  icon/                     # fuente del icono (ver wiki: Icono y Splash)
  sounds/alarm.wav
```

## Contribuir

1. `flutter analyze` y `flutter test` antes de subir cambios.
2. Sigue el estilo del codigo existente: sin comentarios que expliquen el
   "que" (los nombres ya lo dicen), solo el "por que" cuando no es obvio.
3. Abre un PR describiendo el cambio; la wiki tiene el detalle de
   arquitectura si necesitas contexto antes de tocar algo.

## Licencia

Sin licencia definida todavia — todos los derechos reservados por defecto.
