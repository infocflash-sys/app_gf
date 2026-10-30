# Portal Clientes · Grupo Flash

App Android (Flutter) para que los clientes consulten sus piezas, con una API de **solo lectura** (Node) que lee la DB del ERP.

```
app/   App Flutter (Android)
api/   API Node (Fastify) → MariaDB del ERP + FTP de imágenes y PDF
```

## Reglas de negocio vigentes
- Solo entran **clientes activos** (`users.active = 1`, grupo Cliente y `flash_clientes.cliente_estado_id = 1`). Se revalida al abrir la app y cada minuto en la API.
- Cada cliente ve **solo** las piezas vinculadas a su cuenta (pieza → comprobante de ingreso → cliente). Una pieza de otro cliente responde 404.
- La bienvenida usa el **nombre del cliente**, no el del usuario. Se muestra tras el login y la primera vez que se abre la app cada día.
- Sesión permanente hasta desinstalar. La app no recupera claves: remite a www.flashlogistica.com.ar.
- Tarjeta **azul** = estado definitivo (`flash_piezas_estados_variables.pieza_estado_id = 2`); **verde** = en gestión.

## Correr la API
```
cd api
copy .env.example .env     # completar credenciales y JWT_SECRET
npm install
npm start                  # http://localhost:3000
npm test                   # tests unitarios
SMOKE_USER=... SMOKE_PASS=... npm run smoke   # prueba de punta a punta contra la API en marcha
```

## Correr la app
```
cd app
flutter run                                              # emulador Android (usa http://10.0.2.2:3000)
flutter run --dart-define=API_URL=http://IP_DE_TU_PC:3000   # celular real en la misma red
```

## Antes de producción
- Usuario de DB y de FTP **solo lectura** y rotar las claves usadas en desarrollo.
- Publicar la API por **HTTPS** y quitar `usesCleartextTraffic` del `AndroidManifest.xml`.
- Autorizar la IP del servidor de la API en Remote MySQL.
