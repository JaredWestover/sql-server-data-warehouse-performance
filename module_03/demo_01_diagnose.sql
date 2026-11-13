/* =============================================================
   Demo 01: Diagnose a slow warehouse query
   Module 03: Diagnose and tune warehouse queries

   Download the demo files for this course from the following link:
   https://github.com/JaredWestover/sql-server-data-warehouse-performance
============================================================= */

USE DataWarehouseDemo;
GO

-- Check the clustered index's row count, size, and used page count
SELECT
 OBJECT_NAME(ps.object_id)                AS Table_Name,
 SUM(ps.row_count)                        AS Row_Count,
 SUM(ps.reserved_page_count) * 8 / 1024.0 AS Reserved_MB,
 SUM(ps.used_page_count) * 8 / 1024.0     AS Used_MB,
 SUM(ps.used_page_count)                  AS Used_Page_Count
FROM
 sys.dm_db_partition_stats ps
WHERE ps.object_id = OBJECT_ID('dbo.FactSalesCompressed')
      AND ps.index_id = 1
GROUP BY ps.object_id;
GO

-- Review the table's index columns and compression settings
SELECT
 i.name                  AS Index_Name,
 i.type_desc             AS Index_Type,
 i.is_unique             AS Is_Unique,
 c.name                  AS Column_Name,
 ic.key_ordinal          AS Key_Ordinal,
 ic.is_included_column   AS Is_Included_Column,
 p.data_compression_desc AS Compression_Type
FROM
 sys.indexes                  i
 INNER JOIN sys.index_columns ic
  ON ic.object_id = i.object_id
     AND ic.index_id = i.index_id
 INNER JOIN sys.columns       c
  ON c.object_id = ic.object_id
     AND c.column_id = ic.column_id
 INNER JOIN sys.partitions    p
  ON p.object_id = i.object_id
     AND p.index_id = i.index_id
WHERE i.object_id = OBJECT_ID('dbo.FactSalesCompressed')
ORDER BY i.index_id,
         ic.key_ordinal;
GO

/*
Stakeholders run this per-store running-total report multiple times a day.

The query returns one row for each date with sales for the selected store
within the reporting period.

DailySales is the total sales for that date.
RunningTotalSales includes sales from @StartDate through that date.
*/
SET STATISTICS IO, TIME, XML ON;
GO

DECLARE @StoreKey int = 1;
DECLARE @StartDate date = '20260101';
DECLARE @EndDate date = '20260401';

SELECT
 f.OrderDate,
 SUM(f.SalesAmount)                      AS DailySales,
 (SELECT
   SUM(f2.SalesAmount)
  FROM
   dbo.FactSalesCompressed f2
  WHERE f2.StoreKey = @StoreKey
        AND f2.OrderDate >= @StartDate
        AND f2.OrderDate <= f.OrderDate) AS RunningTotalSales
FROM
 dbo.FactSalesCompressed f
WHERE f.StoreKey = @StoreKey
      AND f.OrderDate >= @StartDate
      AND f.OrderDate < @EndDate
GROUP BY f.OrderDate
ORDER BY f.OrderDate;
GO

SET STATISTICS IO, TIME, XML OFF;
GO

-- How do we go about fixing the slowdown?