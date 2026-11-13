/* =============================================================
   Demo 03: Improve estimates after warehouse loads
   Module 03: Diagnose and tune warehouse queries

   Download the demo files for this course from the following link:
   https://github.com/JaredWestover/sql-server-data-warehouse-performance
============================================================= */

USE DataWarehouseDemo;
GO

UPDATE STATISTICS dbo.FactSalesCompressed
 WITH
 FULLSCAN;
GO

/*
Other statistics update options

UPDATE STATISTICS dbo.FactSalesCompressed
 WITH SAMPLE 50 PERCENT;
GO

UPDATE STATISTICS dbo.FactSalesCompressed
 WITH SAMPLE 500000 ROWS;
GO

-- Reuse the previous sampling rate
UPDATE STATISTICS dbo.FactSalesCompressed
 WITH RESAMPLE;
GO

-- Let SQL Server choose the sample size
UPDATE STATISTICS dbo.FactSalesCompressed;
GO
*/

-- Check the current row count and table size
SELECT
 OBJECT_NAME(ps.object_id)                AS Table_Name,
 SUM(ps.row_count)                        AS Row_Count,
 SUM(ps.reserved_page_count) * 8 / 1024.0 AS Reserved_MB,
 SUM(ps.used_page_count) * 8 / 1024.0     AS Used_MB
FROM
 sys.dm_db_partition_stats ps
WHERE ps.object_id = OBJECT_ID('dbo.FactSalesCompressed')
      AND ps.index_id = 1
GROUP BY ps.object_id;
GO

-- Load 300,000 rows for a new date
INSERT INTO dbo.FactSalesCompressed WITH (TABLOCK)
(
 SalesKey,
 OrderNumber,
 PurchaseOrderNumber,
 OrderRiskCategory,
 OrderDate,
 CustomerKey,
 ProductKey,
 StoreKey,
 PromotionKey,
 Quantity,
 SalesAmount,
 DiscountAmount
)
SELECT
 TOP (300000)
 l.SalesKey + 100000000,
 l.OrderNumber,
 l.PurchaseOrderNumber,
 l.OrderRiskCategory,
 CONVERT(date, '20270115'),
 l.CustomerKey,
 l.ProductKey,
 l.StoreKey,
 l.PromotionKey,
 l.Quantity,
 l.SalesAmount,
 l.DiscountAmount
FROM
 dbo.LoadingFactSales l
ORDER BY l.SalesKey;
GO


-- Return the new date's sales, sorted by SalesAmount
SET STATISTICS IO, TIME, XML ON;
GO

SELECT
 f.OrderDate,
 f.SalesKey,
 f.OrderNumber,
 f.OrderRiskCategory,
 f.CustomerKey,
 f.SalesAmount
FROM
 dbo.FactSalesCompressed f
WHERE f.OrderDate = '20270115'
ORDER BY f.SalesAmount DESC,
         f.SalesKey;
GO

SET STATISTICS IO, TIME, XML OFF;
GO


-- Inspect the clustered index statistics after the load
SELECT
 s.name                  AS Statistic_Name,
 sp.last_updated         AS Last_Updated,
 sp.rows                 AS Rows_At_Last_Update,
 sp.rows_sampled         AS Rows_Sampled,
 sp.steps                AS Histogram_Steps,
 sp.modification_counter AS Modifications
FROM
 sys.stats                                                       s
 CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
WHERE s.object_id = OBJECT_ID('dbo.FactSalesCompressed')
      AND s.stats_id = 1;
GO

-- Check the latest date boundaries in the OrderDate histogram
SELECT
 TOP (10)
 h.step_number                   AS Step_Number,
 CONVERT(date, h.range_high_key) AS Histogram_Date,
 h.equal_rows                    AS Rows_For_Date
FROM
 sys.dm_db_stats_histogram(OBJECT_ID('dbo.FactSalesCompressed'), 1) h
ORDER BY h.step_number DESC;
GO

-- Check the OrderDate density in the existing statistics
DBCC SHOW_STATISTICS('dbo.FactSalesCompressed', 'CX_FactSalesCompressed_OrderDate') WITH DENSITY_VECTOR;
GO

-- Calculate the estimate for the new date using the OrderDate All density
SELECT 300000.0 * 0.0003422314 AS Estimated_Rows;
GO

-- Update statistics to include the newly loaded data
UPDATE STATISTICS dbo.FactSalesCompressed
 WITH
 FULLSCAN;
GO

-- Rerun the same query and compare estimates, spills, and metrics
SET STATISTICS IO, TIME, XML ON;
GO

SELECT
 f.OrderDate,
 f.SalesKey,
 f.OrderNumber,
 f.OrderRiskCategory,
 f.CustomerKey,
 f.SalesAmount
FROM
 dbo.FactSalesCompressed f
WHERE f.OrderDate = '20270115'
ORDER BY f.SalesAmount DESC,
         f.SalesKey;
GO

SET STATISTICS IO, TIME, XML OFF;
GO

-- Verify the statistics now reflect the load
SELECT
 s.name                  AS Statistic_Name,
 sp.last_updated         AS Last_Updated,
 sp.rows                 AS Rows_At_Last_Update,
 sp.rows_sampled         AS Rows_Sampled,
 sp.steps                AS Histogram_Steps,
 sp.modification_counter AS Modifications
FROM
 sys.stats                                                       s
 CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
WHERE s.object_id = OBJECT_ID('dbo.FactSalesCompressed')
      AND s.stats_id = 1;
GO

-- Check the histogram for the newly loaded date
SELECT
 TOP (10)
 h.step_number                   AS Step_Number,
 CONVERT(date, h.range_high_key) AS Histogram_Date,
 h.equal_rows                    AS Rows_For_Date
FROM
 sys.dm_db_stats_histogram(OBJECT_ID('dbo.FactSalesCompressed'), 1) h
ORDER BY h.step_number DESC;
GO

-- Microsoft Learn: Statistics - SQL Server
-- https://learn.microsoft.com/en-us/sql/relational-databases/statistics/statistics?view=sql-server-ver17

-- MSSQLTips: Update Statistics SQL Server
-- https://www.mssqltips.com/sqlservertip/6720/update-statistics-sql-server/