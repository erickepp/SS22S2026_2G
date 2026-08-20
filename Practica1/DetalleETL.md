# Detalle del proceso ETL - cargar_modelo.py


## 1. Extracción (`leer_dataset_original`)

- Lee el CSV crudo con `pandas.read_csv(dtype=str, keep_default_na=False)`.
  Todo se conserva como texto y las celdas vacías **no** se convierten a `NaN`
  automáticamente, para no perder el formato original antes de limpiarlo.
- Valida que existan las 26 columnas de `COLUMNAS_ORIGINALES_REQUERIDAS`.
  Si falta alguna, lanza `ValueError` y el proceso se detiene ahí — no hay
  carga parcial con columnas faltantes.
- Selecciona únicamente esas 26 columnas, descartando cualquier columna extra
  que pudiera traer el archivo.

## 2. Transformación (`transformar_dataset`)

### 2.1 Deduplicación y unicidad
- `drop_duplicates()` elimina filas exactamente iguales.
- Si `record_id` tiene duplicados tras eso, lanza `ValueError` de inmediato:
  el dataset de origen debe tener `RecordID` único antes de continuar.

### 2.2 Resolución de fechas (`_resolver_fechas_fila` / `_candidatos_fecha`)
Es la parte más compleja del ETL. El archivo crudo mezcla formatos de fecha
(`DD/MM/AAAA`, `MM/DD/AAAA`, `AAAA-MM-DD`, con AM/PM), por lo que una fecha
como `03/04/2026` es ambigua.

- `_candidatos_fecha` genera **todas** las interpretaciones válidas de un
  valor según el patrón del texto (si contiene `/`, prueba día/mes y
  mes/día; si contiene AM/PM, usa ese formato; si no, formato ISO).
- `_resolver_fechas_fila` combina los candidatos de salida, llegada y
  reserva, y descarta combinaciones que violen las reglas del negocio:
  - `FechaHoraReserva` no puede ser posterior a `FechaHoraSalida`.
  - Si el vuelo está `CANCELLED`, no se exige llegada.
  - Si no está cancelado, la duración implícita (`llegada - salida`) debe
    coincidir con `duration_min + delay_min` con un margen de **30 minutos**.
  - Entre las combinaciones válidas, se elige la de menor "prioridad"
    (favorece formatos DD/MM sobre MM/DD y el menor error de duración).
- Si ninguna combinación es válida, lanza `ValueError` identificando el
  `RecordID` afectado — la fila no se homologa a ciegas.

### 2.3 Homologación de categorías
- **Género**: se normaliza a mayúsculas y se mapea contra un diccionario
  fijo (`M`, `MASCULINO`→`M`, `F`, `FEMENINO`→`F`, `X`, `NOBINARIO`→`X`).
  Cualquier valor fuera de ese diccionario lanza `ValueError` — no se
  homologan valores desconocidos de género, se rechaza todo el dataset.
- **Nacionalidad**: mayúsculas; vacío → `ZZ`.
- **Canal de venta**: mayúsculas; vacío → `DESCONOCIDO`.
- **Precio**: `_convertir_numero(coma_decimal=True)` reemplaza `,` por `.`
  antes de convertir a numérico.
- **PasajeroID**: se normaliza a minúsculas (para consistencia con el hash).

### 2.4 Generación de claves hash (SHA-256)
- **`VueloNaturalKey`**: hash de la concatenación
  `AerolineaCodigo|NumeroVuelo|FechaHoraSalida(ISO)|AeropuertoOrigenCodigo|AeropuertoDestinoCodigo`
  separada por `|`. Identifica la **instancia de vuelo**, independiente del
  pasajero — dos pasajeros en el mismo vuelo comparten esta clave.
- **`HashPasajero`**: hash de `GeneroCodigo|NacionalidadCodigo`. Este es el
  valor que se compara en SQL Server contra `HashAtributos` de
  `DimPasajero` para decidir si abrir una nueva versión SCD Tipo 2.
- Ambos usan `hashlib.sha256(...).hexdigest()` → 64 caracteres hexadecimales.

## 3. Validación (`validar_dataset_limpio`)

Se ejecuta automáticamente al final de `transformar_dataset`, antes de
exportar o conectar con SQL Server. Cualquier fallo lanza `ValueError` y
**detiene todo el proceso** — no hay archivo de rechazados ni carga parcial;
el diseño es "todo o nada" a nivel de archivo completo.

Reglas validadas, en orden:
1. **Estructura**: las 28 columnas esperadas deben existir, sin columnas
   faltantes ni inesperadas.
2. **RecordID**: no nulo, no duplicado.
3. **Campos de texto obligatorios**: 14 columnas no pueden estar vacías ni
   nulas (aerolínea, número de vuelo, aeropuertos, estado, aeronave, clase,
   pasajero, género, nacionalidad, canal, pago, moneda).
4. **Fechas obligatorias**: `FechaHoraSalida` y `FechaHoraReserva` no nulas.
5. **Secuencia temporal en vuelos no cancelados**: `FechaHoraLlegada` no
   nula, `llegada >= salida`, `reserva <= salida`.
6. **Numéricos obligatorios**: `PrecioBoleto`, `PrecioUSD`, `EquipajeTotal`,
   `EquipajeFacturado` no nulos.
7. **Precios**: `PrecioBoleto > 0` y `PrecioUSD > 0`.
8. **Equipaje**: `EquipajeTotal >= 0` y `0 <= EquipajeFacturado <= EquipajeTotal`.
9. **Edad**: si no es nula, debe estar entre 0 y 120.
10. **Formato de `PasajeroID`**: debe cumplir el patrón UUID
    (`8-4-4-4-12` caracteres hexadecimales).
11. **Formato de hashes**: `VueloNaturalKey` y `HashPasajero` deben ser
    cadenas hexadecimales de 64 caracteres.

Estas mismas reglas son el espejo en Python de los `CHECK` constraints
definidos en `modelo_dwh.sql` — la validación ocurre dos veces (antes de
enviar los datos y otra vez al insertarlos en SQL Server), lo que da una
segunda barrera de defensa si el modelo cambiara sin actualizar el ETL.

## 4. Exportación (`guardar_dataset_limpio`)

- Escribe el CSV limpio con `date_format="%Y-%m-%d %H:%M:%S"`, formato
  compatible con `DATETIME2` de SQL Server.
- Crea el directorio destino si no existe (`mkdir(parents=True, exist_ok=True)`).
- **Nota importante**: como se aclara en el README, este archivo se
  regenera en cada ejecución a partir del CSV crudo — nunca se usa como
  entrada, solo como evidencia/auditoría de la transformación.

## 5. Reportes en consola

Antes de tocar la base de datos, el script imprime cuatro tablas (función
`mostrar_resultados`), todas calculadas por comparación reproducible entre
el dataset original y el limpio — no son valores fijos ni simulados:

| Función | Qué muestra |
|---|---|
| `imprimir_muestra_original` | Primeras 10 filas del CSV crudo (columnas clave) |
| `imprimir_muestra_limpia` | Las mismas 10 filas después de transformar |
| `imprimir_resumen_transformaciones` | Conteos de celdas modificadas: aeropuertos normalizados, géneros homologados, fechas con formato alterno, precios con coma convertidos, nacionalidades/canales asignados por defecto |
| `imprimir_resumen_validacion` | RecordID únicos, pasajeros distintos, vuelos distintos, vuelos cancelados, duplicados, y confirmación de estructura compatible |

## 6. Conexión a SQL Server (`crear_motor_desde_entorno`)

- Lee `DB_SERVER`, `DB_DATABASE` (default `VuelosDW`), `DB_USERNAME`,
  `DB_PASSWORD` desde variables de entorno (cargadas con `load_dotenv()` al
  inicio del script, es decir, soporta un archivo `.env`).
- Si falta `DB_SERVER`, `DB_USERNAME` o `DB_PASSWORD`, lanza `ValueError`
  listando exactamente cuáles — no falla con un error genérico de conexión.
- Construye la cadena ODBC con `Encrypt=yes;TrustServerCertificate=yes`,
  necesario porque el driver 18 exige conexión cifrada por defecto.
- El motor SQLAlchemy se crea con `fast_executemany=True` (inserciones por
  lote más eficientes) y `pool_pre_ping=True` (valida la conexión antes de
  usarla, evita fallos por conexiones caducadas).

## 7. Carga transaccional (`cargar_dataset`)

```python
with motor.begin() as conexion:
    # 1. Verifica que existan stg.VuelosLimpios y dwh.usp_CargarDesdeStaging
    # 2. DELETE FROM stg.VuelosLimpios
    # 3. INSERT de todo el dataset limpio a staging (chunksize=1000)
    # 4. EXEC dwh.usp_CargarDesdeStaging @ArchivoOrigen=...
```

- **El procedimiento es atómico** (`motor.begin()`). Si el
  procedimiento almacenado falla a mitad de camino, el `DELETE` de staging
  también se revierte — no queda staging vacío ni a medias.
- **Verificación previa**: antes de tocar datos, confirma que el modelo
  (`stg.VuelosLimpios`) y el procedimiento (`dwh.usp_CargarDesdeStaging`)
  existen. Si no, lanza `RuntimeError` inmediatamente — evita un error
  críptico de SQL más adelante.
- **Resolución de dimensiones, SCD Tipo 2 y hechos se ejecuta en T-SQL**,
  dentro de `dwh.usp_CargarDesdeStaging`, no en Python. El script de Python
  solo prepara y entrega el lote limpio; toda la lógica de idempotencia a
  nivel de hecho (`RecordID` nuevo vs. existente) y de historización del
  pasajero (comparación de `HashAtributos` vigente vs. `HashPasajero`
  recibido) vive en el procedimiento almacenado, no aquí.
- El procedimiento devuelve un conjunto de resultados (conteos) que Python
  captura y muestra en la tabla final `RESULTADO DE LA CARGA DWH` — esta es
  la confirmación de cuántas filas nuevas se insertaron por tabla.
