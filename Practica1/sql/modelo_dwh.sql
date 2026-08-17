/* Crear la base de datos, el modelo dimensional y la vista de consulta. */
USE master;
GO

IF DB_ID(N'VuelosDW') IS NULL
BEGIN
    CREATE DATABASE VuelosDW;
END;
GO

/* Representar un pasajero y una reserva por segmento de vuelo. */
USE VuelosDW;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'stg')
    EXEC(N'CREATE SCHEMA stg');
GO
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'dwh')
    EXEC(N'CREATE SCHEMA dwh');
GO

/* Recibir en staging el lote validado por el programa Python. */
IF OBJECT_ID(N'stg.VuelosLimpios', N'U') IS NULL
BEGIN
    CREATE TABLE stg.VuelosLimpios (
        RecordID                    BIGINT          NOT NULL,
        AerolineaCodigo             VARCHAR(3)      NOT NULL,
        AerolineaNombre             NVARCHAR(100)   NOT NULL,
        NumeroVuelo                 VARCHAR(12)     NOT NULL,
        VueloNaturalKey             CHAR(64)        NOT NULL,
        AeropuertoOrigenCodigo      CHAR(3)         NOT NULL,
        AeropuertoDestinoCodigo     CHAR(3)         NOT NULL,
        FechaHoraSalida             DATETIME2(0)    NOT NULL,
        FechaHoraLlegada            DATETIME2(0)    NULL,
        DuracionMinutos             SMALLINT        NULL,
        EstadoVueloCodigo           VARCHAR(20)     NOT NULL,
        RetrasoMinutos              SMALLINT        NULL,
        TipoAeronaveCodigo          VARCHAR(20)     NOT NULL,
        ClaseCabinaCodigo           VARCHAR(30)     NOT NULL,
        Asiento                     VARCHAR(10)     NULL,
        PasajeroID                  VARCHAR(36)     NOT NULL,
        GeneroCodigo                VARCHAR(5)      NOT NULL,
        EdadPasajero                TINYINT         NULL,
        NacionalidadCodigo          CHAR(2)         NOT NULL,
        FechaHoraReserva            DATETIME2(0)    NOT NULL,
        CanalVentaCodigo            VARCHAR(30)     NOT NULL,
        MetodoPagoCodigo            VARCHAR(30)     NOT NULL,
        PrecioBoleto                DECIMAL(18,2)   NOT NULL,
        MonedaCodigo                CHAR(3)         NOT NULL,
        PrecioUSD                   DECIMAL(18,2)   NOT NULL,
        EquipajeTotal               TINYINT         NOT NULL,
        EquipajeFacturado           TINYINT         NOT NULL,
        HashPasajero                CHAR(64)        NOT NULL
    );
END;
GO

/* Utilizar claves sustitutas para relacionar dimensiones y hechos. */
IF OBJECT_ID(N'dwh.DimFecha', N'U') IS NULL
BEGIN
    CREATE TABLE dwh.DimFecha (
        FechaKey       INT       NOT NULL CONSTRAINT PK_DimFecha PRIMARY KEY,
        Fecha          DATE      NOT NULL CONSTRAINT UQ_DimFecha_Fecha UNIQUE,
        Anio           SMALLINT  NOT NULL,
        Trimestre      TINYINT   NOT NULL,
        Mes            TINYINT   NOT NULL,
        Dia            TINYINT   NOT NULL,
        CONSTRAINT CK_DimFecha_Trimestre CHECK (Trimestre BETWEEN 1 AND 4),
        CONSTRAINT CK_DimFecha_Mes CHECK (Mes BETWEEN 1 AND 12),
        CONSTRAINT CK_DimFecha_Dia CHECK (Dia BETWEEN 1 AND 31)
    );
END;
GO

IF OBJECT_ID(N'dwh.DimAerolinea', N'U') IS NULL
BEGIN
    CREATE TABLE dwh.DimAerolinea (
        AerolineaKey      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DimAerolinea PRIMARY KEY,
        AerolineaCodigo   VARCHAR(3)        NOT NULL CONSTRAINT UQ_DimAerolinea_Codigo UNIQUE,
        AerolineaNombre   NVARCHAR(100)     NOT NULL
    );
END;
GO

IF OBJECT_ID(N'dwh.DimAeropuerto', N'U') IS NULL
BEGIN
    CREATE TABLE dwh.DimAeropuerto (
        AeropuertoKey      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DimAeropuerto PRIMARY KEY,
        AeropuertoCodigo   CHAR(3)           NOT NULL CONSTRAINT UQ_DimAeropuerto_Codigo UNIQUE
    );
END;
GO

IF OBJECT_ID(N'dwh.DimAeronave', N'U') IS NULL
BEGIN
    CREATE TABLE dwh.DimAeronave (
        AeronaveKey          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DimAeronave PRIMARY KEY,
        TipoAeronaveCodigo   VARCHAR(20)       NOT NULL CONSTRAINT UQ_DimAeronave_Codigo UNIQUE
    );
END;
GO

IF OBJECT_ID(N'dwh.DimClaseCabina', N'U') IS NULL
BEGIN
    CREATE TABLE dwh.DimClaseCabina (
        ClaseCabinaKey      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DimClaseCabina PRIMARY KEY,
        ClaseCabinaCodigo   VARCHAR(30)       NOT NULL CONSTRAINT UQ_DimClaseCabina_Codigo UNIQUE
    );
END;
GO

IF OBJECT_ID(N'dwh.DimEstadoVuelo', N'U') IS NULL
BEGIN
    CREATE TABLE dwh.DimEstadoVuelo (
        EstadoVueloKey      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DimEstadoVuelo PRIMARY KEY,
        EstadoVueloCodigo   VARCHAR(20)       NOT NULL CONSTRAINT UQ_DimEstadoVuelo_Codigo UNIQUE
    );
END;
GO

IF OBJECT_ID(N'dwh.DimCanalVenta', N'U') IS NULL
BEGIN
    CREATE TABLE dwh.DimCanalVenta (
        CanalVentaKey      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DimCanalVenta PRIMARY KEY,
        CanalVentaCodigo   VARCHAR(30)       NOT NULL CONSTRAINT UQ_DimCanalVenta_Codigo UNIQUE
    );
END;
GO

IF OBJECT_ID(N'dwh.DimMetodoPago', N'U') IS NULL
BEGIN
    CREATE TABLE dwh.DimMetodoPago (
        MetodoPagoKey      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DimMetodoPago PRIMARY KEY,
        MetodoPagoCodigo   VARCHAR(30)       NOT NULL CONSTRAINT UQ_DimMetodoPago_Codigo UNIQUE
    );
END;
GO

IF OBJECT_ID(N'dwh.DimMoneda', N'U') IS NULL
BEGIN
    CREATE TABLE dwh.DimMoneda (
        MonedaKey      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DimMoneda PRIMARY KEY,
        MonedaCodigo   CHAR(3)           NOT NULL CONSTRAINT UQ_DimMoneda_Codigo UNIQUE
    );
END;
GO

/* Conservar versiones históricas del pasajero mediante SCD Tipo 2. */
IF OBJECT_ID(N'dwh.DimPasajero', N'U') IS NULL
BEGIN
    CREATE TABLE dwh.DimPasajero (
        PasajeroKey         BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DimPasajero PRIMARY KEY,
        PasajeroID          UNIQUEIDENTIFIER     NOT NULL,
        GeneroCodigo        VARCHAR(5)           NOT NULL,
        NacionalidadCodigo  CHAR(2)              NOT NULL,
        HashAtributos       CHAR(64)              NOT NULL,
        FechaInicio         DATETIME2(0)          NOT NULL,
        FechaFin            DATETIME2(0)          NULL,
        EsActual            BIT                   NOT NULL,
        CONSTRAINT CK_DimPasajero_Vigencia CHECK (
            (EsActual = 1 AND FechaFin IS NULL)
            OR
            (EsActual = 0 AND FechaFin IS NOT NULL AND FechaFin >= FechaInicio)
        )
    );

    CREATE UNIQUE NONCLUSTERED INDEX UX_DimPasajero_Actual
        ON dwh.DimPasajero(PasajeroID)
        WHERE EsActual = 1;

    CREATE NONCLUSTERED INDEX IX_DimPasajero_Historial
        ON dwh.DimPasajero(PasajeroID, FechaInicio, FechaFin);
END;
GO

/* Mantener una fila única por RecordID en la tabla de hechos. */
IF OBJECT_ID(N'dwh.FactVueloPasajero', N'U') IS NULL
BEGIN
    CREATE TABLE dwh.FactVueloPasajero (
        FactVueloPasajeroKey    BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_FactVueloPasajero PRIMARY KEY,
        RecordID                 BIGINT          NOT NULL CONSTRAINT UQ_FactVueloPasajero_RecordID UNIQUE,
        VueloNaturalKey          CHAR(64)        NOT NULL,
        FechaSalidaKey           INT             NOT NULL,
        FechaLlegadaKey          INT             NULL,
        FechaReservaKey          INT             NOT NULL,
        AerolineaKey             INT             NOT NULL,
        AeropuertoOrigenKey      INT             NOT NULL,
        AeropuertoDestinoKey     INT             NOT NULL,
        AeronaveKey              INT             NOT NULL,
        ClaseCabinaKey           INT             NOT NULL,
        EstadoVueloKey           INT             NOT NULL,
        CanalVentaKey            INT             NOT NULL,
        MetodoPagoKey            INT             NOT NULL,
        MonedaKey                INT             NOT NULL,
        PasajeroKey              BIGINT          NOT NULL,
        NumeroVuelo              VARCHAR(12)     NOT NULL,
        FechaHoraSalida          DATETIME2(0)    NOT NULL,
        FechaHoraLlegada         DATETIME2(0)    NULL,
        FechaHoraReserva         DATETIME2(0)    NOT NULL,
        DuracionMinutos          SMALLINT        NULL,
        RetrasoMinutos           SMALLINT        NULL,
        Asiento                  VARCHAR(10)     NULL,
        EdadPasajero             TINYINT         NULL,
        PrecioBoleto             DECIMAL(18,2)   NOT NULL,
        PrecioUSD                DECIMAL(18,2)   NOT NULL,
        EquipajeTotal            TINYINT         NOT NULL,
        EquipajeFacturado        TINYINT         NOT NULL,
        ConteoRegistro           TINYINT         NOT NULL CONSTRAINT DF_FactVueloPasajero_Conteo DEFAULT(1),
        ArchivoOrigen            NVARCHAR(260)   NOT NULL,
        FechaCarga               DATETIME2(0)    NOT NULL CONSTRAINT DF_FactVueloPasajero_FechaCarga DEFAULT(SYSUTCDATETIME()),

        CONSTRAINT FK_Fact_FechaSalida FOREIGN KEY (FechaSalidaKey) REFERENCES dwh.DimFecha(FechaKey),
        CONSTRAINT FK_Fact_FechaLlegada FOREIGN KEY (FechaLlegadaKey) REFERENCES dwh.DimFecha(FechaKey),
        CONSTRAINT FK_Fact_FechaReserva FOREIGN KEY (FechaReservaKey) REFERENCES dwh.DimFecha(FechaKey),
        CONSTRAINT FK_Fact_Aerolinea FOREIGN KEY (AerolineaKey) REFERENCES dwh.DimAerolinea(AerolineaKey),
        CONSTRAINT FK_Fact_AeropuertoOrigen FOREIGN KEY (AeropuertoOrigenKey) REFERENCES dwh.DimAeropuerto(AeropuertoKey),
        CONSTRAINT FK_Fact_AeropuertoDestino FOREIGN KEY (AeropuertoDestinoKey) REFERENCES dwh.DimAeropuerto(AeropuertoKey),
        CONSTRAINT FK_Fact_Aeronave FOREIGN KEY (AeronaveKey) REFERENCES dwh.DimAeronave(AeronaveKey),
        CONSTRAINT FK_Fact_ClaseCabina FOREIGN KEY (ClaseCabinaKey) REFERENCES dwh.DimClaseCabina(ClaseCabinaKey),
        CONSTRAINT FK_Fact_EstadoVuelo FOREIGN KEY (EstadoVueloKey) REFERENCES dwh.DimEstadoVuelo(EstadoVueloKey),
        CONSTRAINT FK_Fact_CanalVenta FOREIGN KEY (CanalVentaKey) REFERENCES dwh.DimCanalVenta(CanalVentaKey),
        CONSTRAINT FK_Fact_MetodoPago FOREIGN KEY (MetodoPagoKey) REFERENCES dwh.DimMetodoPago(MetodoPagoKey),
        CONSTRAINT FK_Fact_Moneda FOREIGN KEY (MonedaKey) REFERENCES dwh.DimMoneda(MonedaKey),
        CONSTRAINT FK_Fact_Pasajero FOREIGN KEY (PasajeroKey) REFERENCES dwh.DimPasajero(PasajeroKey),
        CONSTRAINT CK_Fact_Duracion CHECK (DuracionMinutos IS NULL OR DuracionMinutos > 0),
        CONSTRAINT CK_Fact_Retraso CHECK (RetrasoMinutos IS NULL OR RetrasoMinutos >= 0),
        CONSTRAINT CK_Fact_Precios CHECK (PrecioBoleto > 0 AND PrecioUSD > 0),
        CONSTRAINT CK_Fact_Equipaje CHECK (EquipajeTotal >= 0 AND EquipajeFacturado BETWEEN 0 AND EquipajeTotal),
        CONSTRAINT CK_Fact_Conteo CHECK (ConteoRegistro = 1)
    );

    CREATE NONCLUSTERED INDEX IX_Fact_FechaSalida ON dwh.FactVueloPasajero(FechaSalidaKey);
    CREATE NONCLUSTERED INDEX IX_Fact_Aerolinea ON dwh.FactVueloPasajero(AerolineaKey);
    CREATE NONCLUSTERED INDEX IX_Fact_OrigenDestino ON dwh.FactVueloPasajero(AeropuertoOrigenKey, AeropuertoDestinoKey);
    CREATE NONCLUSTERED INDEX IX_Fact_Pasajero ON dwh.FactVueloPasajero(PasajeroKey);
    CREATE NONCLUSTERED INDEX IX_Fact_VueloNatural ON dwh.FactVueloPasajero(VueloNaturalKey);
END;
GO

/* Resolver las claves y exponer nombres adecuados para análisis. */
CREATE OR ALTER VIEW dwh.v_AnalisisVuelos
AS
SELECT
    f.RecordID,
    f.VueloNaturalKey,
    f.NumeroVuelo,
    fs.Fecha AS FechaSalida,
    fl.Fecha AS FechaLlegada,
    fr.Fecha AS FechaReserva,
    fs.Anio AS AnioSalida,
    fs.Trimestre AS TrimestreSalida,
    fs.Mes AS MesSalida,
    fs.Dia AS DiaSalida,
    da.AerolineaCodigo,
    da.AerolineaNombre,
    ao.AeropuertoCodigo AS AeropuertoOrigen,
    ad.AeropuertoCodigo AS AeropuertoDestino,
    dan.TipoAeronaveCodigo,
    dc.ClaseCabinaCodigo,
    de.EstadoVueloCodigo,
    dcv.CanalVentaCodigo,
    dmp.MetodoPagoCodigo,
    dm.MonedaCodigo,
    dp.PasajeroID,
    dp.GeneroCodigo,
    dp.NacionalidadCodigo,
    f.EdadPasajero,
    f.FechaHoraSalida,
    f.FechaHoraLlegada,
    f.FechaHoraReserva,
    f.DuracionMinutos,
    f.RetrasoMinutos,
    f.Asiento,
    f.PrecioBoleto,
    f.PrecioUSD,
    f.EquipajeTotal,
    f.EquipajeFacturado,
    f.ConteoRegistro
FROM dwh.FactVueloPasajero AS f
INNER JOIN dwh.DimFecha AS fs ON fs.FechaKey = f.FechaSalidaKey
LEFT JOIN dwh.DimFecha AS fl ON fl.FechaKey = f.FechaLlegadaKey
INNER JOIN dwh.DimFecha AS fr ON fr.FechaKey = f.FechaReservaKey
INNER JOIN dwh.DimAerolinea AS da ON da.AerolineaKey = f.AerolineaKey
INNER JOIN dwh.DimAeropuerto AS ao ON ao.AeropuertoKey = f.AeropuertoOrigenKey
INNER JOIN dwh.DimAeropuerto AS ad ON ad.AeropuertoKey = f.AeropuertoDestinoKey
INNER JOIN dwh.DimAeronave AS dan ON dan.AeronaveKey = f.AeronaveKey
INNER JOIN dwh.DimClaseCabina AS dc ON dc.ClaseCabinaKey = f.ClaseCabinaKey
INNER JOIN dwh.DimEstadoVuelo AS de ON de.EstadoVueloKey = f.EstadoVueloKey
INNER JOIN dwh.DimCanalVenta AS dcv ON dcv.CanalVentaKey = f.CanalVentaKey
INNER JOIN dwh.DimMetodoPago AS dmp ON dmp.MetodoPagoKey = f.MetodoPagoKey
INNER JOIN dwh.DimMoneda AS dm ON dm.MonedaKey = f.MonedaKey
INNER JOIN dwh.DimPasajero AS dp ON dp.PasajeroKey = f.PasajeroKey;
GO
