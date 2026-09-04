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
- **Dos caminos para cada destino** — *Solo avisarme* (la app vigila el
  acercamiento y suena) o *Buscar ruta de bus*, que calcula que servicios de
  TransMilenio/SITP sirven, con transbordo cuando hace falta, y muestra las
  opciones ordenadas por tiempo puerta a puerta.
- **La ruta no desaparece al arrancar** — durante el viaje se dibuja el
  recorrido completo del bus tenue, y encima tu tramo en naranja: gris lo ya
  recorrido, naranja lo que falta, con todos los paraderos visibles. Tocar
  uno adelante cambia donde te bajas y recalcula los avisos.
- **Nada de buses para media cuadra** — bajo 500 m la app solo propone
  caminar, y no sugiere ningun tramo en bus mas corto que eso.
- **Ruta y tiempo estimado** — calculados con [OSRM](http://project-osrm.org/)
  sobre la red vial real, con un margen extra para tráfico urbano.
- **Avisos escalonados** — primer aviso, segundo aviso (opcional) y alarma
  final, cada uno con su propio umbral en minutos configurable.
- **Los primeros avisos se sienten, no solo se ven** — cuatro rafagas de
  vibracion larga repartidas en ~20 s, no un tic de notificacion. Pensado
  para alguien que se quedo dormido.
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
| Datos de rutas | GTFS de TransMilenio, preprocesado a assets locales (`tool/`) |
| Buses en vivo | GTFS-Realtime de TransMilenio (best-effort, ver abajo) |
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
    alert_service.dart      # avisos + rafagas de vibracion insistentes
    notification_service.dart  # canales Android, sonidos y repeticion iOS
    journey_planner.dart    # opciones puerta a puerta, hasta un transbordo
    transit_index_service.dart # red completa aplanada para el planeador
    live_vehicles_service.dart # posiciones GTFS-Realtime (best-effort)
    location_service.dart   # ciclo de permisos de ubicacion
    alarm_player.dart
    geocoding_service.dart  # Nominatim
    routing_service.dart    # OSRM + heuristica de trafico urbano
    places_history_service.dart
  widgets/
    map_style.dart          # tile layer + atribucion compartidos
assets/
  icon/                     # fuente del icono (ver wiki: Icono y Splash)
  sounds/alarm.wav
  transit/
    routes/<id>.json        # trazado + paraderos de cada ruta
    routes_index.json       # busqueda por codigo de ruta
    planner.json            # red aplanada que usa el planeador
tool/
  build_transit_data.py     # GTFS crudo -> assets por ruta
  shape_snap.py             # donde cae cada paradero sobre el trazado
  backfill_stop_shape_index.py
  build_planner_index.py    # assets por ruta -> planner.json
```

## Datos de transporte

Los assets se generan sin conexion desde el GTFS publico de TransMilenio
(~620 MB descomprimido, imposible de procesar en el telefono):

```bash
python3 tool/build_transit_data.py        # necesita ./gtfs con el feed extraido
python3 tool/build_planner_index.py       # deriva planner.json de los assets
```

`tool/backfill_stop_shape_index.py` solo hace falta para packs viejos, que no
traen `si`/`sm` en cada ruta.

Un detalle que cuesta caro si se hace mal: los paraderos **no** caen sobre los
vertices del trazado, los trazados vienen simplificados (~2 vertices por
paradero) y las rutas zonales recorren el mismo corredor dos veces. Pegar cada
paradero al vertice mas cercano da tramos de 0 m entre paraderos separados por
kilometros. `tool/shape_snap.py` proyecta sobre el segmento y avanza con una
ventana limitada; el resultado se guarda en `si`/`sm` para que la app nunca
tenga que adivinarlo.

## Avisos: que hace cada plataforma

| | Android | iOS |
|---|---|---|
| Aviso temprano | Canal silencioso con patron de vibracion largo + rafagas repetidas desde la app | Notificacion con sonido corto (en iOS una notificacion sin sonido tampoco vibra) |
| Alarma final | `fullScreenIntent`: se sobrepone a lo que haya, incluso bloqueado | Banner + sonido de 28 s, re-publicado 6 veces mientras suena |
| Vibracion en segundo plano | Sale del canal de notificacion, funciona con la app dormida | Core Haptics solo corre en primer plano; con la pantalla bloqueada la vibracion viene del sonido de la notificacion |

**iOS no tiene equivalente de `fullScreenIntent`.** Ninguna app de terceros
puede taparle la pantalla al usuario como hace la de Android. Lo que si se
puede, y esta implementado:

- **Sonido propio de 28 s** (`ios/Runner/Sounds/alarm_long.caf`, el tope de
  iOS son 30 s) en vez del tic por defecto, mas 6 repeticiones de la
  notificacion mientras la alarma sigue activa. Esto **no necesita ningun
  permiso especial** y es la mejora mas grande del lado iOS.
- **`interruptionLevel: timeSensitive`**, que atraviesa los modos de
  Concentracion. Necesita el entitlement
  `com.apple.developer.usernotifications.time-sensitive`, que **las cuentas
  personales (gratuitas) de Apple no permiten** — la firma falla con
  *"Personal development teams ... do not support the Time Sensitive
  Notifications capability"*. Por eso viene apagado: `ios/Runner/Runner.entitlements`
  ya existe, y para activarlo en una cuenta de pago basta poner en
  `ios/Flutter/Debug.xcconfig` y `Release.xcconfig`:

  ```
  ARRIVE_ALERT_ENTITLEMENTS = Runner/Runner.entitlements
  ```

- **Critical Alerts** (se salta el switch de silencio y Concentracion, y fija
  su propio volumen) requiere [aprobacion caso por caso de
  Apple](https://developer.apple.com/contact/request/notifications-critical-alerts-entitlement/).
  El codigo ya pide el permiso en tiempo de ejecucion y cae a `timeSensitive`
  si no lo tiene; al aprobarlo solo hay que descomentar la llave en
  `Runner.entitlements`.

Lo unico que da una alarma a pantalla completa de verdad en iOS es
**AlarmKit** (iOS 26+), que exige codigo Swift nativo y un target de widget
aparte, y programa alarmas por hora — habria que reprogramarla cada vez que
cambia la ETA. No esta implementado.

## Buses en vivo

TransMilenio publica GTFS-Realtime **sin llave** en un host que cambio en
2026 — el viejo (`gis.transmilenio.gov.co/gtfs/*.pb`) responde 500 y no
vuelve:

| Archivo | Que trae | Frecuencia |
|---|---|---|
| `https://gtfs.transmilenio.gov.co/positions.pb` | Posicion de toda la flota (~6400 buses, 630 servicios) | ~15 s |
| `https://gtfs.transmilenio.gov.co/tripupdates.pb` | Retrasos por viaje | ~15 s |
| `https://gtfs.transmilenio.gov.co/alerts.pb` | Alertas de servicio | ~15 s |
| `https://gtfs.transmilenio.gov.co/GTFS.zip` | Feed estatico (~118 MB) | diaria |

El listado vive en `https://gtfs.transmilenio.gov.co/manifest.json`, que es
donde mirar si vuelven a mover las cosas.

Los `route_id` del feed en vivo son los mismos del pack estatico, asi que un
bus se cruza con nuestras rutas sin traduccion (`12819` = B23).

`live_vehicles_service.dart` decodifica el protobuf a mano, sin dependencias
nuevas. Se muestran buses en tres pantallas: el mapa de una ruta, la vista
previa de un viaje planeado, y el viaje en curso (ahi solo los de tu tramo y
cerca tuyo).

`live_vehicles_feed.dart` es el unico worker que consulta: refresca cada 15 s
(lo mismo que publica la agencia) y reparte el resultado a todas las
pantallas por un stream.

**Solo baja cuando el usuario elige ver una ruta.** El worker arranca al
abrir el mapa de una ruta o el viaje en curso, y se apaga cuando esas
pantallas se cierran o la app pasa a segundo plano. La pantalla de opciones
y la vista previa de un viaje **no** traen buses: ahi la app solo recomienda,
y los buses aparecen cuando la persona dice cual ruta quiere ver.

Tocar un bus dice su numero de flota, que servicio corre y hace cuanto
reporto su posicion.

Si una consulta se demora mas de 1.2 s sin nada que mostrar aun, aparece un
snack gris y pequeno ("Buscando buses...") por encima de la tarjeta inferior;
en cuanto llegan los buses se va, y los refrescos siguientes son mudos.

**El costo es real y lo paga cada telefono**: no hay servidor nuestro en
medio, y el feed no deja pedir una sola ruta, asi que cada refresco baja la
flota completa (~830 KB) — del orden de 3 MB por minuto de mapa abierto. Se
mitiga con un solo worker compartido, cache de 12 s, `If-None-Match`, pausa
en segundo plano, y el interruptor de Ajustes → Buses en vivo.

Si algun dia molesta ese consumo, la salida es un proxy propio que baje el
feed una vez y sirva por ruta: dejaria cada consulta en unos pocos KB, a
cambio de mantener un servidor.

El `timestamp` de cabecera del feed viene congelado, asi que la frescura se
saca del timestamp de cada bus y se descartan los de mas de 5 minutos.

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
    alert_service.dart      # avisos + rafagas de vibracion insistentes
    notification_service.dart  # canales Android, sonidos y repeticion iOS
    journey_planner.dart    # opciones puerta a puerta, hasta un transbordo
    transit_index_service.dart # red completa aplanada para el planeador
    live_vehicles_service.dart # posiciones GTFS-Realtime (best-effort)
    location_service.dart   # ciclo de permisos de ubicacion
    alarm_player.dart
    geocoding_service.dart  # Nominatim
    routing_service.dart    # OSRM + heuristica de trafico urbano
    places_history_service.dart
  widgets/
    map_style.dart          # tile layer + atribucion compartidos
assets/
  icon/                     # fuente del icono (ver wiki: Icono y Splash)
  sounds/alarm.wav
  transit/
    routes/<id>.json        # trazado + paraderos de cada ruta
    routes_index.json       # busqueda por codigo de ruta
    planner.json            # red aplanada que usa el planeador
tool/
  build_transit_data.py     # GTFS crudo -> assets por ruta
  shape_snap.py             # donde cae cada paradero sobre el trazado
  backfill_stop_shape_index.py
  build_planner_index.py    # assets por ruta -> planner.json
```

## Datos de transporte

Los assets se generan sin conexion desde el GTFS publico de TransMilenio
(~620 MB descomprimido, imposible de procesar en el telefono):

```bash
python3 tool/build_transit_data.py        # necesita ./gtfs con el feed extraido
python3 tool/build_planner_index.py       # deriva planner.json de los assets
```

`tool/backfill_stop_shape_index.py` solo hace falta para packs viejos, que no
traen `si`/`sm` en cada ruta.

Un detalle que cuesta caro si se hace mal: los paraderos **no** caen sobre los
vertices del trazado, los trazados vienen simplificados (~2 vertices por
paradero) y las rutas zonales recorren el mismo corredor dos veces. Pegar cada
paradero al vertice mas cercano da tramos de 0 m entre paraderos separados por
kilometros. `tool/shape_snap.py` proyecta sobre el segmento y avanza con una
ventana limitada; el resultado se guarda en `si`/`sm` para que la app nunca
tenga que adivinarlo.

## Avisos: que hace cada plataforma

| | Android | iOS |
|---|---|---|
| Aviso temprano | Canal silencioso con patron de vibracion largo + rafagas repetidas desde la app | Notificacion con sonido corto (en iOS una notificacion sin sonido tampoco vibra) |
| Alarma final | `fullScreenIntent`: se sobrepone a lo que haya, incluso bloqueado | Banner + sonido de 28 s, re-publicado 6 veces mientras suena |
| Vibracion en segundo plano | Sale del canal de notificacion, funciona con la app dormida | Core Haptics solo corre en primer plano; con la pantalla bloqueada la vibracion viene del sonido de la notificacion |

**iOS no tiene equivalente de `fullScreenIntent`.** Ninguna app de terceros
puede taparle la pantalla al usuario como hace la de Android. Lo que si se
puede, y esta implementado:

- **Sonido propio de 28 s** (`ios/Runner/Sounds/alarm_long.caf`, el tope de
  iOS son 30 s) en vez del tic por defecto, mas 6 repeticiones de la
  notificacion mientras la alarma sigue activa. Esto **no necesita ningun
  permiso especial** y es la mejora mas grande del lado iOS.
- **`interruptionLevel: timeSensitive`**, que atraviesa los modos de
  Concentracion. Necesita el entitlement
  `com.apple.developer.usernotifications.time-sensitive`, que **las cuentas
  personales (gratuitas) de Apple no permiten** — la firma falla con
  *"Personal development teams ... do not support the Time Sensitive
  Notifications capability"*. Por eso viene apagado: `ios/Runner/Runner.entitlements`
  ya existe, y para activarlo en una cuenta de pago basta poner en
  `ios/Flutter/Debug.xcconfig` y `Release.xcconfig`:

  ```
  ARRIVE_ALERT_ENTITLEMENTS = Runner/Runner.entitlements
  ```

- **Critical Alerts** (se salta el switch de silencio y Concentracion, y fija
  su propio volumen) requiere [aprobacion caso por caso de
  Apple](https://developer.apple.com/contact/request/notifications-critical-alerts-entitlement/).
  El codigo ya pide el permiso en tiempo de ejecucion y cae a `timeSensitive`
  si no lo tiene; al aprobarlo solo hay que descomentar la llave en
  `Runner.entitlements`.

Lo unico que da una alarma a pantalla completa de verdad en iOS es
**AlarmKit** (iOS 26+), que exige codigo Swift nativo y un target de widget
aparte, y programa alarmas por hora — habria que reprogramarla cada vez que
cambia la ETA. No esta implementado.

## Buses en vivo

TransMilenio publica GTFS-Realtime sin llave en
`https://gis.transmilenio.gov.co/gtfs/vehiclepos.pb` (tambien `tripupdate.pb`
y `serviceAlerts.pb`). `live_vehicles_service.dart` lo lee y decodifica el
protobuf a mano, sin dependencias nuevas.

**Estado actual: el endpoint responde HTTP 500** (todo el path `/gtfs/` del
host, no solo ese archivo). El servicio trata cada consulta como best-effort:
si falla, devuelve vacio, se toma 5 minutos de descanso, y el viaje sigue
funcionando con GPS como siempre. Cuando el feed vuelva, los buses aparecen
solos en el mapa del viaje.

## Contribuir

1. `flutter analyze` y `flutter test` antes de subir cambios.
2. Sigue el estilo del codigo existente: sin comentarios que expliquen el
   "que" (los nombres ya lo dicen), solo el "por que" cuando no es obvio.
3. Abre un PR describiendo el cambio; la wiki tiene el detalle de
   arquitectura si necesitas contexto antes de tocar algo.

## Licencia

Sin licencia definida todavia — todos los derechos reservados por defecto.
