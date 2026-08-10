# ============================================================
# TAREA 1 - LIMPIEZA Y ANÁLISIS INICIAL DE DATOS
# Seminario de Sistemas 2 - 2S2026
# ============================================================

import pandas as pd
import matplotlib.pyplot as plt


# ============================================================
# 1. IMPORTACIÓN DEL DATASET
# ============================================================

archivo = "dataset_sucio.csv"

df_original = pd.read_csv(archivo)

# Se crea una copia para realizar el proceso de limpieza.
df = df_original.copy()


# ============================================================
# 2. ESTADO ORIGINAL DEL DATASET
# ============================================================

print("=" * 60)
print("DATAFRAME ORIGINAL")
print("=" * 60)

print("\nPrimeras filas:")
print(df_original.head())

print("\nDimensiones:")
print(df_original.shape)

print("\nTipos de datos:")
print(df_original.dtypes)

print("\nValores faltantes:")
print(df_original.isna().sum())

print("\nDuplicados:")
print(df_original.duplicated().sum())


# ============================================================
# 3. ELIMINACIÓN DE DUPLICADOS
# ============================================================

df = df.drop_duplicates()


# ============================================================
# 4. TRATAMIENTO DE CELDAS VACÍAS
# ============================================================

# Se eliminan espacios innecesarios de las columnas de texto.
df["genero"] = (
    df["genero"]
    .astype("string")
    .str.strip()
)

df["nombre"] = (
    df["nombre"]
    .astype("string")
    .str.strip()
)

df["ciudad"] = (
    df["ciudad"]
    .astype("string")
    .str.strip()
)

df["categoria"] = (
    df["categoria"]
    .astype("string")
    .str.strip()
)


# Se identifican como valores faltantes las celdas vacías
# de género.
df["genero"] = (
    df["genero"]
    .replace("", pd.NA)
)


# Se utiliza la moda para completar los valores faltantes
# de género.
df["genero"] = df["genero"].fillna(
    df["genero"].mode()[0]
)


# Se identifican las ciudades sin información y se utiliza
# una categoría para representarlas.
df["ciudad"] = (
    df["ciudad"]
    .replace("", pd.NA)
    .fillna("Desconocida")
)


# Se convierten los valores del gasto a formato numérico
# antes de completar los valores faltantes.
df["gasto_q"] = pd.to_numeric(
    df["gasto_q"]
    .astype("string")
    .str.strip()
    .str.replace(",", ".", regex=False),
    errors="coerce"
)


# Se utiliza la mediana para completar los valores faltantes
# del gasto.
df["gasto_q"] = df["gasto_q"].fillna(
    df["gasto_q"].median()
)


# ============================================================
# 5. ESTANDARIZACIÓN DE VALORES Y FORMATOS
# ============================================================

# Género
df["genero"] = (
    df["genero"]
    .str.upper()
)


# Nombre
df["nombre"] = (
    df["nombre"]
    .str.title()
)


# Ciudad
df["ciudad"] = (
    df["ciudad"]
    .str.title()
)


# Categoría
df["categoria"] = (
    df["categoria"]
    .str.title()
)


# Fecha
# Se convierten los formatos YYYY-MM-DD y DD/MM/YYYY
# presentes en el dataset.
fechas = (
    df["fecha_registro"]
    .astype("string")
    .str.strip()
)

fecha_iso = pd.to_datetime(
    fechas,
    format="%Y-%m-%d",
    errors="coerce"
)

fecha_dia_mes = pd.to_datetime(
    fechas,
    format="%d/%m/%Y",
    errors="coerce"
)

df["fecha_registro"] = fecha_iso.fillna(
    fecha_dia_mes
)


# ============================================================
# 6. ESTADO DEPURADO DEL DATASET
# ============================================================

print("\n")
print("=" * 60)
print("DATAFRAME DEPURADO")
print("=" * 60)

print("\nPrimeras filas:")
print(df.head())

print("\nDimensiones:")
print(df.shape)

print("\nTipos de datos:")
print(df.dtypes)

print("\nValores faltantes:")
print(df.isna().sum())

print("\nDuplicados:")
print(df.duplicated().sum())


# ============================================================
# 7. TABLA TIPO PIVOTE
# ============================================================

tabla_pivote = pd.pivot_table(
    df,
    index="ciudad",
    values="gasto_q",
    aggfunc="sum"
)

print("\n")
print("=" * 60)
print("TABLA TIPO PIVOTE - GASTO POR CIUDAD")
print("=" * 60)

print(tabla_pivote)


# ============================================================
# 8. VISUALIZACIÓN 1
# ============================================================

# Relación entre ciudad y gasto.
tabla_pivote["gasto_q"].sort_values(
    ascending=False
).plot(
    kind="bar",
    figsize=(10, 6)
)

plt.title("Gasto total por ciudad")
plt.xlabel("Ciudad")
plt.ylabel("Gasto total (Q)")
plt.xticks(rotation=45, ha="right")
plt.tight_layout()

plt.savefig(
    "gasto_por_ciudad.png",
    dpi=300,
    bbox_inches="tight"
)

plt.show()


# ============================================================
# 9. VISUALIZACIÓN 2
# ============================================================

# Relación entre género, categoría y gasto.
tabla_genero_categoria = pd.pivot_table(
    df,
    index="genero",
    columns="categoria",
    values="gasto_q",
    aggfunc="sum",
    fill_value=0
)

print("\n")
print("=" * 60)
print("TABLA TIPO PIVOTE - GÉNERO Y CATEGORÍA")
print("=" * 60)

print(tabla_genero_categoria)


tabla_genero_categoria.plot(
    kind="bar",
    figsize=(10, 6)
)

plt.title("Gasto por género y categoría")
plt.xlabel("Género")
plt.ylabel("Gasto total (Q)")
plt.xticks(rotation=0)
plt.tight_layout()

plt.savefig(
    "gasto_genero_categoria.png",
    dpi=300,
    bbox_inches="tight"
)

plt.show()


# ============================================================
# 10. EXPORTACIÓN DEL DATASET LIMPIO
# ============================================================

df.to_csv(
    "dataset_limpio.csv",
    index=False,
    encoding="utf-8-sig"
)


print("\n")
print("=" * 60)
print("PROCESO FINALIZADO")
print("=" * 60)

print("Dataset limpio: dataset_limpio.csv")
