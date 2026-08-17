/* Ejecutar la carga incremental de dimensiones, SCD Tipo 2 y hechos. */
USE VuelosDW;
GO

CREATE OR ALTER PROCEDURE dwh.usp_CargarDesdeStaging
    @ArchivoOrigen NVARCHAR(260)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Ahora DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @FilasStaging INT = (SELECT COUNT(*) FROM stg.VuelosLimpios);
    DECLARE @HechosExistentes INT;
    DECLARE @HechosInsertados INT;
    DECLARE @PasajerosInsertados INT;
    DECLARE @PasajerosVersionados INT;
    DECLARE @PasajerosNuevos INT;

    /* Evitar cargas vacías o ambiguas mediante condiciones iniciales. */
    IF @FilasStaging = 0
        THROW 50001, 'La tabla stg.VuelosLimpios esta vacia.', 1;

    IF EXISTS (
        SELECT RecordID
        FROM stg.VuelosLimpios
        GROUP BY RecordID
        HAVING COUNT(*) > 1
    )
        THROW 50002, 'Existen RecordID duplicados en staging.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        /* Reunir en DimFecha los roles de salida, llegada y reserva. */
        ;WITH Fechas AS (
            SELECT CAST(FechaHoraSalida AS DATE) AS Fecha FROM stg.VuelosLimpios
            UNION
            SELECT CAST(FechaHoraLlegada AS DATE) FROM stg.VuelosLimpios WHERE FechaHoraLlegada IS NOT NULL
            UNION
            SELECT CAST(FechaHoraReserva AS DATE) FROM stg.VuelosLimpios
        )
        INSERT dwh.DimFecha (FechaKey, Fecha, Anio, Trimestre, Mes, Dia)
        SELECT
            CONVERT(INT, CONVERT(CHAR(8), f.Fecha, 112)),
            f.Fecha,
            YEAR(f.Fecha),
            DATEPART(QUARTER, f.Fecha),
            MONTH(f.Fecha),
            DAY(f.Fecha)
        FROM Fechas AS f
        WHERE NOT EXISTS (
            SELECT 1 FROM dwh.DimFecha AS d WHERE d.Fecha = f.Fecha
        );

        /* Insertar únicamente valores inexistentes en las dimensiones estáticas. */
        INSERT dwh.DimAerolinea (AerolineaCodigo, AerolineaNombre)
        SELECT s.AerolineaCodigo, MAX(s.AerolineaNombre)
        FROM stg.VuelosLimpios AS s
        GROUP BY s.AerolineaCodigo
        HAVING NOT EXISTS (
            SELECT 1 FROM dwh.DimAerolinea AS d
            WHERE d.AerolineaCodigo = s.AerolineaCodigo
        );

        ;WITH Aeropuertos AS (
            SELECT AeropuertoOrigenCodigo AS Codigo FROM stg.VuelosLimpios
            UNION
            SELECT AeropuertoDestinoCodigo FROM stg.VuelosLimpios
        )
        INSERT dwh.DimAeropuerto (AeropuertoCodigo)
        SELECT a.Codigo
        FROM Aeropuertos AS a
        WHERE NOT EXISTS (
            SELECT 1 FROM dwh.DimAeropuerto AS d
            WHERE d.AeropuertoCodigo = a.Codigo
        );

        INSERT dwh.DimAeronave (TipoAeronaveCodigo)
        SELECT DISTINCT s.TipoAeronaveCodigo
        FROM stg.VuelosLimpios AS s
        WHERE NOT EXISTS (
            SELECT 1 FROM dwh.DimAeronave AS d
            WHERE d.TipoAeronaveCodigo = s.TipoAeronaveCodigo
        );

        INSERT dwh.DimClaseCabina (ClaseCabinaCodigo)
        SELECT DISTINCT s.ClaseCabinaCodigo
        FROM stg.VuelosLimpios AS s
        WHERE NOT EXISTS (
            SELECT 1 FROM dwh.DimClaseCabina AS d
            WHERE d.ClaseCabinaCodigo = s.ClaseCabinaCodigo
        );

        INSERT dwh.DimEstadoVuelo (EstadoVueloCodigo)
        SELECT DISTINCT s.EstadoVueloCodigo
        FROM stg.VuelosLimpios AS s
        WHERE NOT EXISTS (
            SELECT 1 FROM dwh.DimEstadoVuelo AS d
            WHERE d.EstadoVueloCodigo = s.EstadoVueloCodigo
        );

        INSERT dwh.DimCanalVenta (CanalVentaCodigo)
        SELECT DISTINCT s.CanalVentaCodigo
        FROM stg.VuelosLimpios AS s
        WHERE NOT EXISTS (
            SELECT 1 FROM dwh.DimCanalVenta AS d
            WHERE d.CanalVentaCodigo = s.CanalVentaCodigo
        );

        INSERT dwh.DimMetodoPago (MetodoPagoCodigo)
        SELECT DISTINCT s.MetodoPagoCodigo
        FROM stg.VuelosLimpios AS s
        WHERE NOT EXISTS (
            SELECT 1 FROM dwh.DimMetodoPago AS d
            WHERE d.MetodoPagoCodigo = s.MetodoPagoCodigo
        );

        INSERT dwh.DimMoneda (MonedaCodigo)
        SELECT DISTINCT s.MonedaCodigo
        FROM stg.VuelosLimpios AS s
        WHERE NOT EXISTS (
            SELECT 1 FROM dwh.DimMoneda AS d
            WHERE d.MonedaCodigo = s.MonedaCodigo
        );

        /* Seleccionar la fila más reciente como versión vigente del pasajero. */
        ;WITH PasajerosOrdenados AS (
            SELECT
                TRY_CONVERT(UNIQUEIDENTIFIER, s.PasajeroID) AS PasajeroID,
                s.GeneroCodigo,
                s.NacionalidadCodigo,
                s.HashPasajero,
                ROW_NUMBER() OVER (
                    PARTITION BY s.PasajeroID
                    ORDER BY s.FechaHoraSalida DESC, s.RecordID DESC
                ) AS NumeroFila
            FROM stg.VuelosLimpios AS s
        )
        SELECT PasajeroID, GeneroCodigo, NacionalidadCodigo, HashPasajero
        INTO #PasajerosFuente
        FROM PasajerosOrdenados
        WHERE NumeroFila = 1;

        IF EXISTS (SELECT 1 FROM #PasajerosFuente WHERE PasajeroID IS NULL)
            THROW 50003, 'Existe un PasajeroID que no puede convertirse a UNIQUEIDENTIFIER.', 1;

        /* Cerrar la versión actual cuando exista una diferencia de hash. */
        UPDATE destino
        SET
            destino.FechaFin = @Ahora,
            destino.EsActual = 0
        FROM dwh.DimPasajero AS destino
        INNER JOIN #PasajerosFuente AS fuente
            ON fuente.PasajeroID = destino.PasajeroID
        WHERE destino.EsActual = 1
          AND destino.HashAtributos <> fuente.HashPasajero;

        SET @PasajerosVersionados = @@ROWCOUNT;

        INSERT dwh.DimPasajero (
            PasajeroID, GeneroCodigo, NacionalidadCodigo, HashAtributos,
            FechaInicio, FechaFin, EsActual
        )
        SELECT
            fuente.PasajeroID,
            fuente.GeneroCodigo,
            fuente.NacionalidadCodigo,
            fuente.HashPasajero,
            @Ahora,
            NULL,
            1
        FROM #PasajerosFuente AS fuente
        WHERE NOT EXISTS (
            SELECT 1
            FROM dwh.DimPasajero AS destino
            WHERE destino.PasajeroID = fuente.PasajeroID
              AND destino.EsActual = 1
        );

        SET @PasajerosInsertados = @@ROWCOUNT;
        SET @PasajerosNuevos = @PasajerosInsertados - @PasajerosVersionados;

        SELECT @HechosExistentes = COUNT(*)
        FROM stg.VuelosLimpios AS s
        INNER JOIN dwh.FactVueloPasajero AS f ON f.RecordID = s.RecordID;

        /* Utilizar RecordID para impedir hechos duplicados en cargas repetidas. */
        INSERT dwh.FactVueloPasajero (
            RecordID, VueloNaturalKey, FechaSalidaKey, FechaLlegadaKey,
            FechaReservaKey, AerolineaKey, AeropuertoOrigenKey,
            AeropuertoDestinoKey, AeronaveKey, ClaseCabinaKey,
            EstadoVueloKey, CanalVentaKey, MetodoPagoKey, MonedaKey,
            PasajeroKey, NumeroVuelo, FechaHoraSalida, FechaHoraLlegada,
            FechaHoraReserva, DuracionMinutos, RetrasoMinutos, Asiento,
            EdadPasajero, PrecioBoleto, PrecioUSD, EquipajeTotal,
            EquipajeFacturado, ConteoRegistro, ArchivoOrigen
        )
        SELECT
            s.RecordID,
            s.VueloNaturalKey,
            fs.FechaKey,
            fl.FechaKey,
            fr.FechaKey,
            da.AerolineaKey,
            ao.AeropuertoKey,
            ad.AeropuertoKey,
            dan.AeronaveKey,
            dc.ClaseCabinaKey,
            de.EstadoVueloKey,
            dcv.CanalVentaKey,
            dmp.MetodoPagoKey,
            dm.MonedaKey,
            dp.PasajeroKey,
            s.NumeroVuelo,
            s.FechaHoraSalida,
            s.FechaHoraLlegada,
            s.FechaHoraReserva,
            s.DuracionMinutos,
            s.RetrasoMinutos,
            s.Asiento,
            s.EdadPasajero,
            s.PrecioBoleto,
            s.PrecioUSD,
            s.EquipajeTotal,
            s.EquipajeFacturado,
            1,
            @ArchivoOrigen
        FROM stg.VuelosLimpios AS s
        INNER JOIN dwh.DimFecha AS fs ON fs.Fecha = CAST(s.FechaHoraSalida AS DATE)
        LEFT JOIN dwh.DimFecha AS fl ON fl.Fecha = CAST(s.FechaHoraLlegada AS DATE)
        INNER JOIN dwh.DimFecha AS fr ON fr.Fecha = CAST(s.FechaHoraReserva AS DATE)
        INNER JOIN dwh.DimAerolinea AS da ON da.AerolineaCodigo = s.AerolineaCodigo
        INNER JOIN dwh.DimAeropuerto AS ao ON ao.AeropuertoCodigo = s.AeropuertoOrigenCodigo
        INNER JOIN dwh.DimAeropuerto AS ad ON ad.AeropuertoCodigo = s.AeropuertoDestinoCodigo
        INNER JOIN dwh.DimAeronave AS dan ON dan.TipoAeronaveCodigo = s.TipoAeronaveCodigo
        INNER JOIN dwh.DimClaseCabina AS dc ON dc.ClaseCabinaCodigo = s.ClaseCabinaCodigo
        INNER JOIN dwh.DimEstadoVuelo AS de ON de.EstadoVueloCodigo = s.EstadoVueloCodigo
        INNER JOIN dwh.DimCanalVenta AS dcv ON dcv.CanalVentaCodigo = s.CanalVentaCodigo
        INNER JOIN dwh.DimMetodoPago AS dmp ON dmp.MetodoPagoCodigo = s.MetodoPagoCodigo
        INNER JOIN dwh.DimMoneda AS dm ON dm.MonedaCodigo = s.MonedaCodigo
        INNER JOIN dwh.DimPasajero AS dp ON dp.PasajeroID = TRY_CONVERT(UNIQUEIDENTIFIER, s.PasajeroID) AND dp.EsActual = 1
        WHERE NOT EXISTS (
            SELECT 1 FROM dwh.FactVueloPasajero AS f WHERE f.RecordID = s.RecordID
        );

        SET @HechosInsertados = @@ROWCOUNT;

        IF @HechosInsertados + @HechosExistentes <> @FilasStaging
            THROW 50004, 'No todas las filas de staging pudieron relacionarse con dimensiones.', 1;

        COMMIT TRANSACTION;

        SELECT
            @FilasStaging AS FilasStaging,
            @HechosInsertados AS HechosInsertados,
            @HechosExistentes AS HechosExistentes,
            @PasajerosNuevos AS PasajerosNuevos,
            @PasajerosVersionados AS PasajerosVersionados;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

/* Validar la integridad mediante las consultas posteriores a la carga. */
SELECT 'Staging' AS Objeto, COUNT(*) AS Filas FROM stg.VuelosLimpios
UNION ALL
SELECT 'Hechos', COUNT(*) FROM dwh.FactVueloPasajero
UNION ALL
SELECT 'Pasajeros', COUNT(*) FROM dwh.DimPasajero;
GO

/* Comprobar que el resultado contenga cero filas. */
SELECT RecordID, COUNT(*) AS Repeticiones
FROM dwh.FactVueloPasajero
GROUP BY RecordID
HAVING COUNT(*) > 1;
GO

/* Comprobar que exista solo una versión actual por pasajero. */
SELECT PasajeroID, COUNT(*) AS VersionesActuales
FROM dwh.DimPasajero
WHERE EsActual = 1
GROUP BY PasajeroID
HAVING COUNT(*) > 1;
GO

/* Comprobar que los tres indicadores sean cero. */
SELECT
    SUM(CASE WHEN EsActual = 1 AND FechaFin IS NOT NULL THEN 1 ELSE 0 END) AS ActualConFechaFin,
    SUM(CASE WHEN EsActual = 0 AND FechaFin IS NULL THEN 1 ELSE 0 END) AS HistoricoSinFechaFin,
    SUM(CASE WHEN FechaFin < FechaInicio THEN 1 ELSE 0 END) AS VigenciaInvertida
FROM dwh.DimPasajero;
GO

/* Comprobar una diferencia de cero durante la primera carga completa. */
SELECT
    (SELECT COUNT(*) FROM stg.VuelosLimpios) AS FilasStaging,
    (SELECT COUNT(*) FROM dwh.FactVueloPasajero) AS FilasHechos,
    (SELECT COUNT(*) FROM stg.VuelosLimpios)
        - (SELECT COUNT(*) FROM dwh.FactVueloPasajero) AS Diferencia;
GO

/* Verificar los nulos esperados en vuelos cancelados. */
SELECT
    EstadoVueloCodigo,
    COUNT(*) AS Registros,
    SUM(CASE WHEN FechaHoraLlegada IS NULL THEN 1 ELSE 0 END) AS SinLlegada,
    SUM(CASE WHEN DuracionMinutos IS NULL THEN 1 ELSE 0 END) AS SinDuracion,
    SUM(CASE WHEN RetrasoMinutos IS NULL THEN 1 ELSE 0 END) AS SinRetraso
FROM dwh.v_AnalisisVuelos
GROUP BY EstadoVueloCodigo
ORDER BY EstadoVueloCodigo;
GO
