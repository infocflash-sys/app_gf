import 'dotenv/config';

const req = (k) => {
  const v = process.env[k];
  if (!v) throw new Error(`Falta la variable de entorno ${k}`);
  return v;
};

export const config = {
  port: Number(process.env.PORT || 3000),
  host: process.env.HOST || '0.0.0.0',
  db: {
    host: req('DB_HOST'),
    port: Number(process.env.DB_PORT || 3306),
    user: req('DB_USER'),
    password: req('DB_PASS'),
    database: req('DB_NAME'),
  },
  ftp: {
    host: req('FTP_HOST'),
    user: req('FTP_USER'),
    password: req('FTP_PASS'),
    root: process.env.FTP_ROOT || '/archivoscompartidos.intranetflash.com/public',
    poolSize: Number(process.env.FTP_POOL || 3),
  },
  jwtSecret: req('JWT_SECRET'),
  accessTtl: process.env.ACCESS_TTL || '30m',
  refreshTtl: process.env.REFRESH_TTL || '400d',
  cacheDir: process.env.CACHE_DIR || './cache',
  piezasDiasDefault: Number(process.env.PIEZAS_DIAS || 30),
  ruteoDb: process.env.RUTEO_DB || 'intran23_ruteo',
  // Reglas del negocio
  recorridoAbierto: 0, // ruteo.grupo_asignacion.estado: solo 0 (abierto) se consulta; cualquier otro valor no.
  estadoEnDistribucion: 2, // flash_piezas_estados_variables.id "En distribucion": único estado con seguimiento en vivo
  segundosSinSenal: 15 * 60, // pasado este tiempo sin puntos GPS se avisa "sin señal reciente"
  groupCliente: 4, // users_groups.group_id = Cliente
  clienteActivo: 1, // flash_clientes_estados: 1 Activo, 2 Inactivo, 3 Suspendido
  estadoDefinitivo: 2, // flash_piezas_estados_variables.pieza_estado_id que marca estado definitivo
};
