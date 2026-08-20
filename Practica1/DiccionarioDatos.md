# Diccionario de datos - VuelosDW

## stg.VuelosLimpios

Tabla de staging. Recibe el lote validado y transformado por el proceso ETL en Python antes de resolverse contra el modelo dimensional.

| Columna | Tipo | Nulo | Descripción |
|---|---|---|---|
| RecordID | BIGINT | No | Identificador del registro en el archivo de origen. Base de la idempotencia de carga. |
| AerolineaCodigo | VARCHAR(3) | No | Código IATA/interno de la aerolínea. |
| AerolineaNombre | NVARCHAR(100) | No | Nombre comercial de la aerolínea. |
| NumeroVuelo | VARCHAR(12) | No | Número de vuelo tal como fue operado. |
| VueloNaturalKey | CHAR(64) | No | Hash SHA-256 que identifica la instancia de vuelo (aerolínea + número + fecha/hora salida + origen + destino). |
| AeropuertoOrigenCodigo | CHAR(3) | No | Código IATA del aeropuerto de origen. |
| AeropuertoDestinoCodigo | CHAR(3) | No | Código IATA del aeropuerto de destino. |
| FechaHoraSalida | DATETIME2(0) | No | Fecha y hora reales o programadas de salida. |
| FechaHoraLlegada | DATETIME2(0) | Sí | Fecha y hora de llegada. Nula si el vuelo fue cancelado. |
| DuracionMinutos | SMALLINT | Sí | Duración del vuelo en minutos. |
| EstadoVueloCodigo | VARCHAR(20) | No | Estado del vuelo (por ejemplo, aterrizado, cancelado). |
| RetrasoMinutos | SMALLINT | Sí | Minutos de retraso respecto al horario programado. |
| TipoAeronaveCodigo | VARCHAR(20) | No | Modelo o tipo de aeronave. |
| ClaseCabinaCodigo | VARCHAR(30) | No | Clase de cabina de la reserva. |
| Asiento | VARCHAR(10) | Sí | Número/letra de asiento asignado. |
| PasajeroID | VARCHAR(36) | No | Identificador natural del pasajero (formato GUID en texto). |
| GeneroCodigo | VARCHAR(5) | No | Género homologado a M, F o X. |
| EdadPasajero | TINYINT | Sí | Edad del pasajero al momento del vuelo. |
| NacionalidadCodigo | CHAR(2) | No | Código de país. `ZZ` si es desconocida. |
| FechaHoraReserva | DATETIME2(0) | No | Fecha y hora en que se realizó la reserva. |
| CanalVentaCodigo | VARCHAR(30) | No | Canal por el que se vendió el boleto. `DESCONOCIDO` si falta. |
| MetodoPagoCodigo | VARCHAR(30) | No | Método de pago utilizado. |
| PrecioBoleto | DECIMAL(18,2) | No | Precio del boleto en la moneda original. |
| MonedaCodigo | CHAR(3) | No | Código ISO de la moneda original. |
| PrecioUSD | DECIMAL(18,2) | No | Precio convertido a dólares estadounidenses. |
| EquipajeTotal | TINYINT | No | Total de piezas de equipaje declaradas. |
| EquipajeFacturado | TINYINT | No | Piezas de equipaje efectivamente facturadas. |
| HashPasajero | CHAR(64) | No | Hash SHA-256 de los atributos del pasajero (género + nacionalidad), usado para detectar cambios en SCD Tipo 2. |

---

## dwh.DimFecha

Dimensión de rol múltiple: se referencia desde el hecho como fecha de salida, llegada y reserva.

| Columna | Tipo | Nulo | Clave | Descripción |
|---|---|---|---|---|
| FechaKey | INT | No | PK | Clave con formato `AAAAMMDD`. |
| Fecha | DATE | No | UNIQUE | Fecha calendario. |
| Anio | SMALLINT | No | | Año de la fecha. |
| Trimestre | TINYINT | No | | Trimestre (1 a 4). |
| Mes | TINYINT | No | | Mes (1 a 12). |
| Dia | TINYINT | No | | Día del mes (1 a 31). |

---

## dwh.DimAerolinea

| Columna | Tipo | Nulo | Clave | Descripción |
|---|---|---|---|---|
| AerolineaKey | INT (IDENTITY) | No | PK | Clave sustituta. |
| AerolineaCodigo | VARCHAR(3) | No | UNIQUE | Código natural de la aerolínea. |
| AerolineaNombre | NVARCHAR(100) | No | | Nombre comercial. |

---

## dwh.DimAeropuerto

Dimensión de rol múltiple: se referencia desde el hecho como aeropuerto de origen y de destino.

| Columna | Tipo | Nulo | Clave | Descripción |
|---|---|---|---|---|
| AeropuertoKey | INT (IDENTITY) | No | PK | Clave sustituta. |
| AeropuertoCodigo | CHAR(3) | No | UNIQUE | Código IATA del aeropuerto. |

---

## dwh.DimAeronave

| Columna | Tipo | Nulo | Clave | Descripción |
|---|---|---|---|---|
| AeronaveKey | INT (IDENTITY) | No | PK | Clave sustituta. |
| TipoAeronaveCodigo | VARCHAR(20) | No | UNIQUE | Modelo o tipo de aeronave. |

---

## dwh.DimClaseCabina

| Columna | Tipo | Nulo | Clave | Descripción |
|---|---|---|---|---|
| ClaseCabinaKey | INT (IDENTITY) | No | PK | Clave sustituta. |
| ClaseCabinaCodigo | VARCHAR(30) | No | UNIQUE | Clase de cabina (económica, ejecutiva, etc.). |

---

## dwh.DimEstadoVuelo

| Columna | Tipo | Nulo | Clave | Descripción |
|---|---|---|---|---|
| EstadoVueloKey | INT (IDENTITY) | No | PK | Clave sustituta. |
| EstadoVueloCodigo | VARCHAR(20) | No | UNIQUE | Estado del vuelo (aterrizado, cancelado, etc.). |

---

## dwh.DimCanalVenta

| Columna | Tipo | Nulo | Clave | Descripción |
|---|---|---|---|---|
| CanalVentaKey | INT (IDENTITY) | No | PK | Clave sustituta. |
| CanalVentaCodigo | VARCHAR(30) | No | UNIQUE | Canal de venta del boleto. |

---

## dwh.DimMetodoPago

| Columna | Tipo | Nulo | Clave | Descripción |
|---|---|---|---|---|
| MetodoPagoKey | INT (IDENTITY) | No | PK | Clave sustituta. |
| MetodoPagoCodigo | VARCHAR(30) | No | UNIQUE | Método de pago utilizado. |

---

## dwh.DimMoneda

| Columna | Tipo | Nulo | Clave | Descripción |
|---|---|---|---|---|
| MonedaKey | INT (IDENTITY) | No | PK | Clave sustituta. |
| MonedaCodigo | CHAR(3) | No | UNIQUE | Código ISO de la moneda original del boleto. |

---

## dwh.DimPasajero

Dimensión de cambio lento (SCD Tipo 2). Conserva el historial de género y nacionalidad del pasajero.

| Columna | Tipo | Nulo | Clave | Descripción |
|---|---|---|---|---|
| PasajeroKey | BIGINT (IDENTITY) | No | PK | Clave sustituta, distinta por cada versión del pasajero. |
| PasajeroID | UNIQUEIDENTIFIER | No | | Clave natural del pasajero (constante entre versiones). |
| GeneroCodigo | VARCHAR(5) | No | | Género vigente en esta versión. |
| NacionalidadCodigo | CHAR(2) | No | | Nacionalidad vigente en esta versión. |
| HashAtributos | CHAR(64) | No | | Hash SHA-256 de género + nacionalidad; detecta cambios frente al staging. |
| FechaInicio | DATETIME2(0) | No | | Inicio de vigencia de la versión. |
| FechaFin | DATETIME2(0) | Sí | | Fin de vigencia. Nula mientras la versión esté activa. |
| EsActual | BIT | No | | Indica si es la versión vigente. Solo una fila por `PasajeroID` puede tener `EsActual = 1` (índice único filtrado). |

---

## dwh.FactVueloPasajero

Tabla de hechos. Grano: una fila por pasajero, reserva y segmento de vuelo.

| Columna | Tipo | Nulo | Clave | Descripción |
|---|---|---|---|---|
| FactVueloPasajeroKey | BIGINT (IDENTITY) | No | PK | Clave sustituta del hecho. |
| RecordID | BIGINT | No | UNIQUE | Identificador del registro origen; garantiza idempotencia de la carga. |
| VueloNaturalKey | CHAR(64) | No | | Hash SHA-256 que identifica la instancia de vuelo (independiente del pasajero). |
| FechaSalidaKey | INT | No | FK → DimFecha | Fecha de salida del vuelo. |
| FechaLlegadaKey | INT | Sí | FK → DimFecha | Fecha de llegada. Nula si el vuelo fue cancelado. |
| FechaReservaKey | INT | No | FK → DimFecha | Fecha en que se realizó la reserva. |
| AerolineaKey | INT | No | FK → DimAerolinea | Aerolínea operadora. |
| AeropuertoOrigenKey | INT | No | FK → DimAeropuerto | Aeropuerto de origen. |
| AeropuertoDestinoKey | INT | No | FK → DimAeropuerto | Aeropuerto de destino. |
| AeronaveKey | INT | No | FK → DimAeronave | Tipo de aeronave. |
| ClaseCabinaKey | INT | No | FK → DimClaseCabina | Clase de cabina de la reserva. |
| EstadoVueloKey | INT | No | FK → DimEstadoVuelo | Estado final del vuelo. |
| CanalVentaKey | INT | No | FK → DimCanalVenta | Canal por el que se vendió el boleto. |
| MetodoPagoKey | INT | No | FK → DimMetodoPago | Método de pago. |
| MonedaKey | INT | No | FK → DimMoneda | Moneda original del precio. |
| PasajeroKey | BIGINT | No | FK → DimPasajero | Versión del pasajero vigente al momento del evento. |
| NumeroVuelo | VARCHAR(12) | No | | Número de vuelo operado. |
| FechaHoraSalida | DATETIME2(0) | No | | Fecha y hora de salida (grano fino, complementa `FechaSalidaKey`). |
| FechaHoraLlegada | DATETIME2(0) | Sí | | Fecha y hora de llegada. |
| FechaHoraReserva | DATETIME2(0) | No | | Fecha y hora de la reserva. |
| DuracionMinutos | SMALLINT | Sí | | Duración del vuelo en minutos. Debe ser mayor a 0 si no es nula. |
| RetrasoMinutos | SMALLINT | Sí | | Minutos de retraso. Debe ser mayor o igual a 0 si no es nula. |
| Asiento | VARCHAR(10) | Sí | | Asiento asignado. |
| EdadPasajero | TINYINT | Sí | | Edad del pasajero en el momento del vuelo (valor observado, no derivado de fecha de nacimiento). |
| PrecioBoleto | DECIMAL(18,2) | No | | Precio en la moneda original. Debe ser mayor a 0. |
| PrecioUSD | DECIMAL(18,2) | No | | Precio normalizado a USD. Debe ser mayor a 0. |
| EquipajeTotal | TINYINT | No | | Piezas de equipaje totales. Debe ser mayor o igual a 0. |
| EquipajeFacturado | TINYINT | No | | Piezas facturadas. Debe estar entre 0 y `EquipajeTotal`. |
| ConteoRegistro | TINYINT | No | | Siempre 1; facilita sumas de conteo. Valor por defecto 1. |
| ArchivoOrigen | NVARCHAR(260) | No | | Nombre del archivo de origen de la carga. |
| FechaCarga | DATETIME2(0) | No | | Marca de tiempo UTC de inserción del hecho. Valor por defecto `SYSUTCDATETIME()`. |

---

## dwh.v_AnalisisVuelos

Vista de consulta. No almacena datos; resuelve las claves sustitutas del hecho contra sus dimensiones para exponer valores descriptivos listos para análisis.

| Columna | Origen | Descripción |
|---|---|---|
| RecordID | FactVueloPasajero | Identificador del registro. |
| VueloNaturalKey | FactVueloPasajero | Identificador de la instancia de vuelo. |
| NumeroVuelo | FactVueloPasajero | Número de vuelo. |
| FechaSalida | DimFecha (rol salida) | Fecha calendario de salida. |
| FechaLlegada | DimFecha (rol llegada) | Fecha calendario de llegada. |
| FechaReserva | DimFecha (rol reserva) | Fecha calendario de la reserva. |
| AnioSalida / TrimestreSalida / MesSalida / DiaSalida | DimFecha (rol salida) | Jerarquía temporal de la salida. |
| AerolineaCodigo / AerolineaNombre | DimAerolinea | Identificación de la aerolínea. |
| AeropuertoOrigen | DimAeropuerto (rol origen) | Código del aeropuerto de origen. |
| AeropuertoDestino | DimAeropuerto (rol destino) | Código del aeropuerto de destino. |
| TipoAeronaveCodigo | DimAeronave | Tipo de aeronave. |
| ClaseCabinaCodigo | DimClaseCabina | Clase de cabina. |
| EstadoVueloCodigo | DimEstadoVuelo | Estado del vuelo. |
| CanalVentaCodigo | DimCanalVenta | Canal de venta. |
| MetodoPagoCodigo | DimMetodoPago | Método de pago. |
| MonedaCodigo | DimMoneda | Moneda original. |
| PasajeroID / GeneroCodigo / NacionalidadCodigo | DimPasajero | Atributos del pasajero vigentes en esa versión. |
| EdadPasajero, FechaHoraSalida, FechaHoraLlegada, FechaHoraReserva, DuracionMinutos, RetrasoMinutos, Asiento, PrecioBoleto, PrecioUSD, EquipajeTotal, EquipajeFacturado, ConteoRegistro | FactVueloPasajero | Medidas y atributos degenerados del hecho. |