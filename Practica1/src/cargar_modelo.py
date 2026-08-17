"""
Extraer, transformar y cargar datos de vuelos en un modelo dimensional de SQL Server.

Funciones principales:
  1) Extraer el dataset crudo.
  2) Limpiar, homologar, estandarizar y exportar el dataset limpio.
  3) Presentar muestras y resultados reproducibles en consola.
  4) Cargar staging y ejecutar el procedimiento incremental del DWH.

Requisitos: Python 3.10+, pandas, SQLAlchemy, pyodbc y ODBC Driver 18.
"""

from __future__ import annotations

from datetime import datetime
import hashlib
import os
from pathlib import Path
from urllib.parse import quote_plus

import pandas as pd


# ============================================================
# 1. CONFIGURACIÓN DE COLUMNAS
# ============================================================

# Definir el esquema esperado para detectar columnas faltantes o inesperadas.
COLUMNAS_LIMPIAS = (
    "RecordID", "AerolineaCodigo", "AerolineaNombre", "NumeroVuelo",
    "VueloNaturalKey", "AeropuertoOrigenCodigo", "AeropuertoDestinoCodigo",
    "FechaHoraSalida", "FechaHoraLlegada", "DuracionMinutos",
    "EstadoVueloCodigo", "RetrasoMinutos", "TipoAeronaveCodigo",
    "ClaseCabinaCodigo", "Asiento", "PasajeroID", "GeneroCodigo",
    "EdadPasajero", "NacionalidadCodigo", "FechaHoraReserva",
    "CanalVentaCodigo", "MetodoPagoCodigo", "PrecioBoleto",
    "MonedaCodigo", "PrecioUSD", "EquipajeTotal", "EquipajeFacturado",
    "HashPasajero",
)

COLUMNAS_ORIGINALES_REQUERIDAS = (
    "record_id", "airline_code", "airline_name", "flight_number",
    "origin_airport", "destination_airport", "departure_datetime",
    "arrival_datetime", "duration_min", "status", "delay_min",
    "aircraft_type", "cabin_class", "seat", "passenger_id",
    "passenger_gender", "passenger_age", "passenger_nationality",
    "booking_datetime", "sales_channel", "payment_method",
    "ticket_price", "currency", "ticket_price_usd_est",
    "bags_total", "bags_checked",
)

RUTA_DATASET_ORIGINAL = Path("data/dataset_vuelos_crudo.csv")
RUTA_DATASET_LIMPIO = Path("data/dataset_vuelos_limpio.csv")


# ============================================================
# 2. EXTRACCIÓN DEL DATASET
# ============================================================

def leer_dataset_original(ruta: Path) -> pd.DataFrame:
    """Leer el CSV crudo como texto para conservar sus formatos originales."""
    if not ruta.is_file():
        raise FileNotFoundError(f"No existe el dataset original: {ruta}")

    datos = pd.read_csv(ruta, dtype=str, keep_default_na=False)
    faltantes = [columna for columna in COLUMNAS_ORIGINALES_REQUERIDAS if columna not in datos]
    if faltantes:
        raise ValueError(f"El dataset original no contiene las columnas: {faltantes}")
    return datos.loc[:, COLUMNAS_ORIGINALES_REQUERIDAS].copy()


# ============================================================
# 3. TRANSFORMACIÓN Y VALIDACIÓN
# ============================================================

def _normalizar_texto(serie: pd.Series) -> pd.Series:
    """Eliminar espacios y homologar valores de texto en mayúsculas."""
    return serie.astype("string").str.strip().str.upper()


def _convertir_numero(serie: pd.Series, coma_decimal: bool = False) -> pd.Series:
    """Convertir una columna de texto a valores numéricos."""
    valores = serie.astype("string").str.strip().replace("", pd.NA)
    if coma_decimal:
        valores = valores.str.replace(",", ".", regex=False)
    return pd.to_numeric(valores, errors="coerce")


def _candidatos_fecha(valor: object) -> list[tuple[pd.Timestamp, int]]:
    """Obtener las interpretaciones válidas de una fecha del archivo crudo."""
    texto = str(valor).strip()
    if not texto:
        return [(pd.NaT, 0)]

    if "/" in texto:
        formatos = ("%d/%m/%Y %H:%M", "%m/%d/%Y %H:%M")
    elif "AM" in texto.upper() or "PM" in texto.upper():
        formatos = ("%m-%d-%Y %I:%M %p",)
    else:
        formatos = ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M")

    candidatos = []
    for prioridad, formato in enumerate(formatos):
        try:
            fecha = pd.Timestamp(datetime.strptime(texto, formato))
        except ValueError:
            continue
        if all(fecha != candidato for candidato, _ in candidatos):
            candidatos.append((fecha, prioridad))

    if not candidatos:
        raise ValueError(f"Formato de fecha no reconocido: {texto}")
    return candidatos


def _resolver_fechas_fila(fila: object) -> tuple[pd.Timestamp, pd.Timestamp, pd.Timestamp]:
    """Resolver fechas ambiguas mediante las reglas temporales del vuelo."""
    salidas = _candidatos_fecha(fila.departure_datetime)
    llegadas = _candidatos_fecha(fila.arrival_datetime)
    reservas = _candidatos_fecha(fila.booking_datetime)
    estado = str(fila.status).strip().upper()
    duracion = pd.to_numeric(fila.duration_min, errors="coerce")
    retraso = pd.to_numeric(fila.delay_min, errors="coerce")
    opciones = []

    # Priorizar DD/MM y utilizar MM/DD cuando la secuencia temporal lo requiera.
    for salida, prioridad_salida in salidas:
        for reserva, prioridad_reserva in reservas:
            if pd.isna(salida) or pd.isna(reserva) or reserva > salida:
                continue

            if estado == "CANCELLED":
                prioridad = (
                    prioridad_salida + prioridad_reserva,
                    prioridad_salida,
                    prioridad_reserva,
                )
                opciones.append((prioridad, salida, pd.NaT, reserva))
                continue

            if pd.isna(duracion) or pd.isna(retraso):
                continue

            for llegada, prioridad_llegada in llegadas:
                if pd.isna(llegada) or llegada < salida:
                    continue
                diferencia = (llegada - salida).total_seconds() / 60
                error_duracion = abs(diferencia - (duracion + retraso))
                if error_duracion > 30:
                    continue
                prioridad = (
                    prioridad_salida + prioridad_llegada + prioridad_reserva,
                    error_duracion,
                    prioridad_salida,
                    prioridad_llegada,
                    prioridad_reserva,
                )
                opciones.append((prioridad, salida, llegada, reserva))

    if not opciones:
        raise ValueError(
            f"No fue posible resolver las fechas del RecordID={fila.record_id}."
        )

    _, salida, llegada, reserva = min(opciones, key=lambda opcion: opcion[0])
    return salida, llegada, reserva


def _crear_hash(texto: str) -> str:
    """Generar un identificador SHA-256 reproducible."""
    return hashlib.sha256(texto.encode("utf-8")).hexdigest()


def transformar_dataset(original: pd.DataFrame) -> pd.DataFrame:
    """Limpiar, homologar y estandarizar el dataset extraído."""
    fuente = original.drop_duplicates().reset_index(drop=True)
    if fuente["record_id"].astype("string").str.strip().duplicated().any():
        raise ValueError("El dataset original contiene RecordID duplicados.")

    fechas = [_resolver_fechas_fila(fila) for fila in fuente.itertuples(index=False)]
    genero = _normalizar_texto(fuente["passenger_gender"]).map({
        "M": "M", "MASCULINO": "M",
        "F": "F", "FEMENINO": "F",
        "X": "X", "NOBINARIO": "X",
    })
    if genero.isna().any():
        raise ValueError("El dataset original contiene valores de género no reconocidos.")
    nacionalidad = _normalizar_texto(
        fuente["passenger_nationality"]
    ).replace("", "ZZ")
    canal_venta = _normalizar_texto(
        fuente["sales_channel"]
    ).replace("", "DESCONOCIDO")

    limpio = pd.DataFrame({
        "RecordID": _convertir_numero(fuente["record_id"]).astype("Int64"),
        "AerolineaCodigo": _normalizar_texto(fuente["airline_code"]),
        "AerolineaNombre": _normalizar_texto(fuente["airline_name"]),
        "NumeroVuelo": _normalizar_texto(fuente["flight_number"]),
        "AeropuertoOrigenCodigo": _normalizar_texto(fuente["origin_airport"]),
        "AeropuertoDestinoCodigo": _normalizar_texto(fuente["destination_airport"]),
        "FechaHoraSalida": [fecha[0] for fecha in fechas],
        "FechaHoraLlegada": [fecha[1] for fecha in fechas],
        "DuracionMinutos": _convertir_numero(fuente["duration_min"]).astype("Int64"),
        "EstadoVueloCodigo": _normalizar_texto(fuente["status"]),
        "RetrasoMinutos": _convertir_numero(fuente["delay_min"]).astype("Int64"),
        "TipoAeronaveCodigo": _normalizar_texto(fuente["aircraft_type"]),
        "ClaseCabinaCodigo": _normalizar_texto(fuente["cabin_class"]),
        "Asiento": _normalizar_texto(fuente["seat"]).replace("", pd.NA),
        "PasajeroID": fuente["passenger_id"].astype("string").str.strip().str.lower(),
        "GeneroCodigo": genero,
        "EdadPasajero": _convertir_numero(fuente["passenger_age"]).astype("Int64"),
        "NacionalidadCodigo": nacionalidad,
        "FechaHoraReserva": [fecha[2] for fecha in fechas],
        "CanalVentaCodigo": canal_venta,
        "MetodoPagoCodigo": _normalizar_texto(fuente["payment_method"]),
        "PrecioBoleto": _convertir_numero(fuente["ticket_price"], coma_decimal=True),
        "MonedaCodigo": _normalizar_texto(fuente["currency"]),
        "PrecioUSD": _convertir_numero(fuente["ticket_price_usd_est"]),
        "EquipajeTotal": _convertir_numero(fuente["bags_total"]).astype("Int64"),
        "EquipajeFacturado": _convertir_numero(fuente["bags_checked"]).astype("Int64"),
    })

    claves_vuelo = limpio.apply(
        lambda fila: "|".join((
            fila["AerolineaCodigo"],
            fila["NumeroVuelo"],
            pd.Timestamp(fila["FechaHoraSalida"]).isoformat(),
            fila["AeropuertoOrigenCodigo"],
            fila["AeropuertoDestinoCodigo"],
        )),
        axis=1,
    )
    limpio.insert(4, "VueloNaturalKey", claves_vuelo.map(_crear_hash))
    limpio["HashPasajero"] = (
        limpio["GeneroCodigo"] + "|" + limpio["NacionalidadCodigo"]
    ).map(_crear_hash)
    return validar_dataset_limpio(limpio)


def validar_dataset_limpio(datos: pd.DataFrame) -> pd.DataFrame:
    """Comprobar las reglas del dataset transformado antes de cargar el DWH."""
    faltantes = [columna for columna in COLUMNAS_LIMPIAS if columna not in datos]
    inesperadas = [columna for columna in datos.columns if columna not in COLUMNAS_LIMPIAS]
    if faltantes or inesperadas:
        raise ValueError(
            f"Estructura del dataset inválida. Faltantes={faltantes}; "
            f"inesperadas={inesperadas}"
        )
    datos = datos.loc[:, COLUMNAS_LIMPIAS].copy()

    # Convertir las fechas antes de evaluar las reglas de nulabilidad.
    for columna in ("FechaHoraSalida", "FechaHoraLlegada", "FechaHoraReserva"):
        datos[columna] = pd.to_datetime(datos[columna], format="mixed", errors="coerce")

    if datos["RecordID"].isna().any() or datos["RecordID"].duplicated().any():
        raise ValueError("RecordID contiene valores vacíos o duplicados.")

    texto_obligatorio = (
        "AerolineaCodigo", "AerolineaNombre", "NumeroVuelo",
        "AeropuertoOrigenCodigo", "AeropuertoDestinoCodigo",
        "EstadoVueloCodigo", "TipoAeronaveCodigo", "ClaseCabinaCodigo",
        "PasajeroID", "GeneroCodigo", "NacionalidadCodigo",
        "CanalVentaCodigo", "MetodoPagoCodigo", "MonedaCodigo",
    )
    for columna in texto_obligatorio:
        vacios = datos[columna].isna() | datos[columna].astype("string").str.strip().eq("")
        if vacios.any():
            raise ValueError(f"{columna} contiene valores vacíos.")

    if datos["FechaHoraSalida"].isna().any() or datos["FechaHoraReserva"].isna().any():
        raise ValueError("Existen fechas obligatorias inválidas.")

    vuelos_completados = datos["EstadoVueloCodigo"].ne("CANCELLED")
    if datos.loc[vuelos_completados, "FechaHoraLlegada"].isna().any():
        raise ValueError("Existen vuelos no cancelados sin fecha de llegada.")
    if (
        datos.loc[vuelos_completados, "FechaHoraLlegada"]
        < datos.loc[vuelos_completados, "FechaHoraSalida"]
    ).any() or (datos["FechaHoraReserva"] > datos["FechaHoraSalida"]).any():
        raise ValueError("Existen fechas que no respetan la secuencia temporal.")

    numericas_obligatorias = (
        "PrecioBoleto", "PrecioUSD", "EquipajeTotal", "EquipajeFacturado",
    )
    if datos.loc[:, list(numericas_obligatorias)].isna().any().any():
        raise ValueError("Existen valores numéricos obligatorios inválidos.")
    if (datos[["PrecioBoleto", "PrecioUSD"]] <= 0).any().any():
        raise ValueError("Los precios deben ser mayores que cero.")
    if (
        (datos["EquipajeTotal"] < 0)
        | (datos["EquipajeFacturado"] < 0)
        | (datos["EquipajeFacturado"] > datos["EquipajeTotal"])
    ).any():
        raise ValueError("Las cantidades de equipaje son inválidas.")
    if not datos["EdadPasajero"].dropna().between(0, 120).all():
        raise ValueError("Existen edades fuera del rango permitido.")

    pasajero_id_valido = datos["PasajeroID"].astype("string").str.fullmatch(
        r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}",
        na=False,
    )
    if not pasajero_id_valido.all():
        raise ValueError("PasajeroID contiene identificadores inválidos.")

    vuelo_valido = datos["VueloNaturalKey"].astype("string").str.fullmatch(
        r"[0-9a-f]{64}", na=False
    )
    pasajero_valido = datos["HashPasajero"].astype("string").str.fullmatch(
        r"[0-9a-f]{64}", na=False
    )
    if not vuelo_valido.all():
        raise ValueError("VueloNaturalKey contiene hashes inválidos.")
    if not pasajero_valido.all():
        raise ValueError("HashPasajero contiene hashes inválidos.")
    return datos


def guardar_dataset_limpio(datos: pd.DataFrame, ruta: Path) -> None:
    """Exportar el resultado estandarizado con un formato compatible con SQL Server."""
    ruta.parent.mkdir(parents=True, exist_ok=True)
    datos.to_csv(
        ruta,
        index=False,
        encoding="utf-8",
        date_format="%Y-%m-%d %H:%M:%S",
    )


# ============================================================
# 4. FORMATO DE TABLAS PARA CONSOLA
# ============================================================

def _texto_celda(valor: object) -> str:
    """Convertir valores de pandas a texto compacto para las tablas de consola."""
    if pd.isna(valor) or valor == "":
        return "NULL"
    if isinstance(valor, pd.Timestamp):
        return valor.strftime("%Y-%m-%d %H:%M")
    if isinstance(valor, float):
        return str(int(valor)) if valor.is_integer() else f"{valor:g}"
    return str(valor)


def imprimir_tabla(titulo: str, tabla: pd.DataFrame) -> None:
    """Imprimir un DataFrame como tabla ASCII reproducible en cualquier terminal."""
    encabezados = [str(columna) for columna in tabla.columns]
    filas = [[_texto_celda(valor) for valor in fila] for fila in tabla.itertuples(index=False)]
    anchos = [
        max(len(encabezado), *(len(fila[indice]) for fila in filas))
        for indice, encabezado in enumerate(encabezados)
    ]

    borde = "+-" + "-+-".join("-" * ancho for ancho in anchos) + "-+"
    separador = "+=" + "=+=".join("=" * ancho for ancho in anchos) + "=+"

    print("=" * len(borde))
    print(titulo)
    print("=" * len(borde))
    print(borde)
    print("| " + " | ".join(texto.ljust(anchos[i]) for i, texto in enumerate(encabezados)) + " |")
    print(separador)
    for fila in filas:
        print("| " + " | ".join(texto.ljust(anchos[i]) for i, texto in enumerate(fila)) + " |")
    print(borde)


# ============================================================
# 5. MUESTRAS Y RESUMEN DE TRANSFORMACIONES
# ============================================================

def imprimir_muestra_original(datos: pd.DataFrame) -> None:
    """Presentar diez filas crudas con las columnas más útiles para comparar."""
    muestra = datos.loc[:, [
        "record_id", "origin_airport", "destination_airport",
        "departure_datetime", "status", "passenger_gender",
        "ticket_price",
    ]].head(10).rename(columns={
        "record_id": "ID",
        "origin_airport": "Origen",
        "destination_airport": "Destino",
        "departure_datetime": "Salida",
        "status": "Estado",
        "passenger_gender": "Género",
        "ticket_price": "Precio",
    })
    imprimir_tabla("DATASET ORIGINAL - PRIMEROS 10 REGISTROS", muestra)


def imprimir_muestra_limpia(datos: pd.DataFrame) -> None:
    """Presentar las mismas variables después de la estandarización."""
    muestra = datos.loc[:, [
        "RecordID", "AeropuertoOrigenCodigo", "AeropuertoDestinoCodigo",
        "FechaHoraSalida", "EstadoVueloCodigo", "GeneroCodigo",
        "PrecioBoleto",
    ]].head(10).rename(columns={
        "RecordID": "ID",
        "AeropuertoOrigenCodigo": "Origen",
        "AeropuertoDestinoCodigo": "Destino",
        "FechaHoraSalida": "Salida",
        "EstadoVueloCodigo": "Estado",
        "GeneroCodigo": "Género",
        "PrecioBoleto": "Precio",
    })
    imprimir_tabla("DATASET LIMPIO - PRIMEROS 10 REGISTROS", muestra)


def calcular_resumen_transformaciones(
    original: pd.DataFrame, limpio: pd.DataFrame
) -> pd.DataFrame:
    """Calcular métricas comprobables mediante la comparación de ambos datasets."""
    fuente = original.drop_duplicates().copy()
    destino = limpio.copy()
    fuente["_id"] = fuente["record_id"].astype(str)
    destino["_id"] = destino["RecordID"].astype(str)
    comparacion = fuente.merge(destino, on="_id", how="inner", validate="one_to_one")

    aeropuertos = int(
        comparacion["origin_airport"].str.strip().ne(
            comparacion["AeropuertoOrigenCodigo"].astype(str)
        ).sum()
        + comparacion["destination_airport"].str.strip().ne(
            comparacion["AeropuertoDestinoCodigo"].astype(str)
        ).sum()
    )
    generos = int(
        comparacion["passenger_gender"].str.strip().ne(
            comparacion["GeneroCodigo"].astype(str)
        ).sum()
    )

    # Considerar como formato base día/mes/año con hora de 24 horas.
    patron_fecha = r"\d{2}/\d{2}/\d{4} \d{2}:\d{2}"
    fechas_alternas = 0
    for columna in ("departure_datetime", "arrival_datetime", "booking_datetime"):
        valores = original[columna].str.strip()
        fechas_alternas += int(
            (valores.ne("") & ~valores.str.fullmatch(patron_fecha, na=False)).sum()
        )

    filas = [
        ("Registros del dataset original", len(original)),
        ("Registros aceptados en el dataset limpio", len(limpio)),
        ("Registros rechazados", max(len(original) - len(limpio), 0)),
        ("Celdas de aeropuerto normalizadas", aeropuertos),
        ("Valores de género homologados", generos),
        ("Fechas con formato alterno estandarizadas", fechas_alternas),
        ("Precios con coma decimal convertidos", int(original["ticket_price"].str.contains(",", regex=False).sum())),
        ("Nacionalidades desconocidas asignadas a ZZ", int(original["passenger_nationality"].str.strip().eq("").sum())),
        ("Canales desconocidos asignados", int(original["sales_channel"].str.strip().eq("").sum())),
    ]
    return pd.DataFrame(filas, columns=["Indicador", "Resultado"])


def imprimir_resumen_transformaciones(original: pd.DataFrame, limpio: pd.DataFrame) -> None:
    """Mostrar los cambios cuantificados sin alterar ninguno de los archivos."""
    resumen = calcular_resumen_transformaciones(original, limpio)
    imprimir_tabla("RESUMEN DE TRANSFORMACIONES", resumen)


def resumen_validacion(datos: pd.DataFrame) -> pd.DataFrame:
    """Construir los indicadores que respaldan la carga del modelo dimensional."""
    cancelados = int(datos["EstadoVueloCodigo"].eq("CANCELLED").sum())
    filas = [
        ("Registros leídos", len(datos)),
        ("RecordID únicos", datos["RecordID"].nunique()),
        ("Pasajeros distintos", datos["PasajeroID"].nunique()),
        ("Vuelos distintos", datos["VueloNaturalKey"].nunique()),
        ("Vuelos cancelados", cancelados),
        ("RecordID duplicados", int(datos["RecordID"].duplicated().sum())),
        ("Estructura compatible con el DWH", "SÍ"),
    ]
    return pd.DataFrame(filas, columns=["Validación", "Resultado"])


def imprimir_resumen_validacion(datos: pd.DataFrame) -> None:
    """Imprimir la validación previa a la conexión con SQL Server."""
    imprimir_tabla("VALIDACIÓN DEL DATASET LIMPIO", resumen_validacion(datos))


# ============================================================
# 6. CONEXIÓN CON SQL SERVER
# ============================================================

def crear_motor_desde_entorno():
    """Crear una conexión SQLAlchemy a partir de variables de entorno."""
    valores = {
        "DB_SERVER": os.getenv("DB_SERVER", ""),
        "DB_DATABASE": os.getenv("DB_DATABASE", "VuelosDW"),
        "DB_USERNAME": os.getenv("DB_USERNAME", ""),
        "DB_PASSWORD": os.getenv("DB_PASSWORD", ""),
    }
    faltantes = [nombre for nombre, valor in valores.items() if not valor]
    if faltantes:
        raise ValueError("Faltan variables de entorno: " + ", ".join(faltantes))

    controlador = os.getenv("DB_DRIVER", "ODBC Driver 18 for SQL Server")
    cadena = (
        f"DRIVER={{{controlador}}};"
        f"SERVER={valores['DB_SERVER']};"
        f"DATABASE={valores['DB_DATABASE']};"
        f"UID={valores['DB_USERNAME']};"
        f"PWD={valores['DB_PASSWORD']};"
        "Encrypt=yes;TrustServerCertificate=yes;"
    )

    # Importar SQLAlchemy de forma diferida para generar reportes sin pyodbc.
    from sqlalchemy import create_engine

    return create_engine(
        "mssql+pyodbc:///?odbc_connect=" + quote_plus(cadena),
        future=True,
        pool_pre_ping=True,
        fast_executemany=True,
    )


# ============================================================
# 7. CARGA TRANSACCIONAL DEL DWH
# ============================================================

def cargar_dataset(datos: pd.DataFrame, archivo_origen: str) -> dict[str, int]:
    """Cargar staging y ejecutar el procedimiento DWH dentro de una transacción."""
    from sqlalchemy import text

    motor = crear_motor_desde_entorno()
    try:
        with motor.begin() as conexion:
            objetos = conexion.execute(text("""
                SELECT
                  CASE WHEN OBJECT_ID(N'stg.VuelosLimpios', N'U') IS NULL THEN 0 ELSE 1 END AS StageExiste,
                  CASE WHEN OBJECT_ID(N'dwh.usp_CargarDesdeStaging', N'P') IS NULL THEN 0 ELSE 1 END AS ProcedimientoExiste;
            """)).mappings().one()
            if not objetos["StageExiste"] or not objetos["ProcedimientoExiste"]:
                raise RuntimeError("El modelo o el procedimiento de carga no están instalados.")

            # Reemplazar staging con el lote procesado en la transacción actual.
            conexion.execute(text("DELETE FROM stg.VuelosLimpios;"))
            datos.to_sql(
                "VuelosLimpios",
                con=conexion,
                schema="stg",
                if_exists="append",
                index=False,
                chunksize=1_000,
            )
            resultado = conexion.execute(
                text("EXEC dwh.usp_CargarDesdeStaging @ArchivoOrigen=:archivo;"),
                {"archivo": archivo_origen},
            ).mappings().one()
        return {nombre: int(valor) for nombre, valor in resultado.items()}
    finally:
        motor.dispose()


# ============================================================
# 8. PRESENTACIÓN DE RESULTADOS
# ============================================================

def mostrar_resultados(original: pd.DataFrame, limpio: pd.DataFrame) -> None:
    """Mostrar en una sola ejecución las tablas de comparación y validación."""
    imprimir_muestra_original(original)
    imprimir_muestra_limpia(limpio)
    imprimir_resumen_transformaciones(original, limpio)
    imprimir_resumen_validacion(limpio)


# ============================================================
# 9. EJECUCIÓN PRINCIPAL
# ============================================================

def main() -> int:
    """Ejecutar el proceso ETL completo desde el dataset original."""
    ruta_original = RUTA_DATASET_ORIGINAL
    datos_originales = leer_dataset_original(ruta_original)
    datos_limpios = transformar_dataset(datos_originales)
    guardar_dataset_limpio(datos_limpios, RUTA_DATASET_LIMPIO)
    mostrar_resultados(datos_originales, datos_limpios)

    resultado = cargar_dataset(datos_limpios, ruta_original.name)
    imprimir_tabla(
        "RESULTADO DE LA CARGA DWH",
        pd.DataFrame(resultado.items(), columns=["Indicador", "Resultado"]),
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
