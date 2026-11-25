# EdgeCam

Maneja tu **DJI Osmo Nano** desde un **Garmin Edge**: un campo de datos que empieza y para la grabación con el botón
de vuelta (Lap), te enseña la batería y el espacio que le queda a la cámara, te avisa si algo va mal y apunta en la
actividad cuándo grabaste cada clip.

Gratis y de código abierto. **Versión beta**: probada con una Osmo Nano y un Edge 540, todavía no en muchas rutas.

[Read in English](README.md)

## Qué necesitas

- Una **DJI Osmo Nano**. Otras DJI no están probadas.
- Un **Garmin Edge 540 / 540 Solar**, que es el probado. También se compila para el Edge 840, 550, 850, 1040 y 1050,
  pero en esos solo se ha probado en el simulador.

## Instalar

Por ahora se instala a mano: todavía no está en la tienda Connect IQ.

1. Descarga el archivo de tu Edge de la [página de versiones](../../releases):
   `EdgeCam-edge540.prg` (Edge 540 / 540 Solar), `EdgeCam-edge840.prg`, `EdgeCam-edge550.prg`,
   `EdgeCam-edge850.prg`, `EdgeCam-edge1040.prg` (1040 / 1040 Solar) o `EdgeCam-edge1050.prg`.
2. Conecta el Edge al ordenador por USB.
   - En Windows aparece como un dispositivo más.
   - En Mac hace falta un programa MTP, como [OpenMTP](https://openmtp.ganeshrvel.com/).
3. Copia ese archivo en la carpeta `Garmin/Apps/` del Edge.
4. Desconecta el Edge. El campo aparece entre los campos Connect IQ.

## Puesta en marcha

1. **Añade el campo** a una pantalla de datos: *Perfiles de actividad → tu perfil → Pantallas de datos → elige un
   campo → Connect IQ → EdgeCam*. Cuanto más grande el hueco, mejor se lee.
2. **Activa sus avisos**: en el mismo perfil, *Alertas* → activa las de Connect IQ / EdgeCam. Sin esto, el campo no
   te puede avisar.
3. **Empareja la cámara**: cierra DJI Mimo (y cualquier otra app que use la cámara) en el móvil, enciende la Nano y
   entra en la pantalla del campo. El campo se pone en ámbar con un **código de 4 cifras** y la Nano enseña una
   «Solicitud de conexión» con el mismo código: pulsa **Aceptar**. Solo la primera vez.

## Uso

**Inicia la actividad** y pulsa **Lap**: la Nano empieza a grabar. **Lap** otra vez: para. Cada pulsación también
marca una vuelta en la actividad.

El color del campo dice el estado:

| Color | Significa |
|---|---|
| Azul marino | Lista, con la batería y el espacio libre de la cámara |
| Rojo | Grabando, con el contador y el piloto parpadeando |
| Ámbar | Hace falta algo: aceptar el código en la cámara, esperar a que la cámara confirme (*REC…* / *STOP…*), o la cámara no responde (*Sin señal*) |
| Gris claro | Buscando o conectando con la cámara |

**Avisos** a pantalla completa (si los activaste):

- Grabación parada: la cámara dejó de grabar sin que la pararas tú, por calor, falta de espacio o su propio botón.
- Cámara perdida grabando, o la cámara no responde.
- Batería de la cámara al 20 % y al 10 %.
- Queda poco espacio en la cámara (menos de 2 GB).

**Paradas**: si tienes la pausa automática, en los semáforos la cámara sigue como estaba. Si la actividad lleva
en pausa **más de 2 minutos**, el campo para la cámara, y siempre la para al guardar o descartar la actividad.
El tiempo se cambia en la app **Garmin Connect** (tu Edge → Connect IQ → EdgeCam → Ajustes): nunca, 1, 2, 5 o
10 minutos.

**Encontrar cada vídeo en la ruta**: el campo guarda en la actividad, segundo a segundo, si la cámara grababa y qué
número de clip era. En Garmin Connect salen como gráficas, *Grabación de la cámara* y *Clip de la cámara*, y el clip
3 es el tercer tramo grabado.

## Límites

- **Lap solo llega al campo con la actividad en marcha**: ni antes de iniciarla ni mientras está en pausa. En una
  parada, graba o para con el botón de la Nano.
- **La batería es una estimación** a partir del voltaje de la cámara (el porcentaje exacto no le llega al Edge).
  Puede variar varios puntos, sobre todo mientras graba.
- **Sin GPS en el vídeo ni marcadores**: la Nano no los admite.
- La Nano no tiene un protocolo de mando publicado por DJI. EdgeCam usa el que se averiguó observando otra app, y una
  actualización de la cámara podría dejarlo sin funcionar.

## Privacidad

EdgeCam no usa internet ni manda nada a nadie. Todo queda entre tu Edge y tu cámara. En el Edge guarda un
identificador al azar para que la cámara lo reconozca. Los datos de grabación van en el archivo de la actividad, así
que viajan con ella si la subes a Garmin Connect, Strava, etc.

## Si algo falla

- **Se queda en «Buscando la cámara»**: la Nano tiene que estar encendida y con la pantalla activa, y ninguna otra
  app conectada a ella.
- **No salen los avisos**: actívalos en las alertas del perfil (ver *Puesta en marcha*).
- **Para informar de un fallo**, abre una incidencia con el modelo de Edge, la versión de firmware de la Nano y qué
  pasó.

Para desarrolladores: [cómo está hecho](docs/DEVELOPMENT.md) y [qué se sabe del protocolo](docs/PROTOCOL.md).

## Créditos y licencia

Parte de [BiciCAM](https://github.com/apradoperez/bicicam) (BiciLAB Factory SL), que a su vez parte de Kamerad, de
Horst Tellioglu. Los nombres de las órdenes vienen de [dji-firmware-tools](https://github.com/o-gs/dji-firmware-tools).
La fuente grande es Barlow Condensed (SIL Open Font License 1.1).

[Licencia MIT](LICENSE). Se entrega sin garantía.

DJI y Osmo son marcas de sus dueños, igual que Garmin y Edge. EdgeCam no tiene relación con DJI ni con Garmin, ni
cuenta con su respaldo.
