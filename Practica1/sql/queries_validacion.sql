USE VuelosDW;
GO
-- NUMERO DE VUELOS

SELECT df.Anio, df.Mes, COUNT(*) AS TotalReservas
FROM dwh.FactVueloPasajero f
JOIN dwh.DimFecha df ON df.FechaKey = f.FechaSalidaKey
GROUP BY df.Anio, df.Mes
ORDER BY df.Anio, df.Mes;


--Destinos frecuentes
SELECT TOP 10 ad.AeropuertoCodigo AS AeropuertoDestino, COUNT(*) AS TotalVuelos
FROM dwh.FactVueloPasajero f
JOIN dwh.DimAeropuerto ad ON ad.AeropuertoKey = f.AeropuertoDestinoKey
GROUP BY ad.AeropuertoCodigo
ORDER BY TotalVuelos DESC;


-- distribucion por genero
SELECT dp.GeneroCodigo, COUNT(*) AS TotalPasajeros,
       CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER() AS DECIMAL(5,2)) AS Porcentaje
FROM dwh.FactVueloPasajero f
JOIN dwh.DimPasajero dp ON dp.PasajeroKey = f.PasajeroKey
GROUP BY dp.GeneroCodigo;


-- puntualidad por aerolina
SELECT da.AerolineaNombre,
       AVG(CAST(f.RetrasoMinutos AS FLOAT)) AS RetrasoPromedioMin,
       SUM(CASE WHEN f.RetrasoMinutos > 0 THEN 1 ELSE 0 END) AS VuelosConRetraso,
       COUNT(*) AS TotalVuelos,
       (SUM(CASE WHEN f.RetrasoMinutos > 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) as Porcentaje
FROM dwh.FactVueloPasajero f
JOIN dwh.DimAerolinea da ON da.AerolineaKey = f.AerolineaKey
GROUP BY da.AerolineaNombre
ORDER BY RetrasoPromedioMin DESC;

-- Ingresos por aerolinea y mes
SELECT da.AerolineaNombre, df.Anio, df.Mes,
       SUM(f.PrecioUSD) AS IngresoTotalUSD,
       AVG(f.PrecioUSD) AS TicketPromedioUSD
FROM dwh.FactVueloPasajero f
JOIN dwh.DimAerolinea da ON da.AerolineaKey = f.AerolineaKey
JOIN dwh.DimFecha df ON df.FechaKey = f.FechaSalidaKey
GROUP BY da.AerolineaNombre, df.Anio, df.Mes
ORDER BY df.Anio, df.Mes, IngresoTotalUSD DESC;


-- rutas mas transitadas
SELECT TOP 10 ao.AeropuertoCodigo AS AeropuertoOrigen,
       ad.AeropuertoCodigo AS AeropuertoDestino,
       COUNT(*) AS TotalVuelos
FROM dwh.FactVueloPasajero f
JOIN dwh.DimAeropuerto ao ON ao.AeropuertoKey = f.AeropuertoOrigenKey
JOIN dwh.DimAeropuerto ad ON ad.AeropuertoKey = f.AeropuertoDestinoKey
GROUP BY ao.AeropuertoCodigo, ad.AeropuertoCodigo
ORDER BY TotalVuelos DESC;


