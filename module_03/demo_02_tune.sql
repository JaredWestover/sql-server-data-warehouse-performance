/* =============================================================
   Demo 02: Tune an analytical query
   Module 03: Diagnose and tune warehouse queries

   Download the demo files for this course from the following link:
   https://github.com/JaredWestover/sql-server-data-warehouse-performance
============================================================= */

USE DataWarehouseDemo;
GO

-- Check for missing index recommendations
-- Microsoft Learn: Tune nonclustered indexes with missing index suggestions
-- https://learn.microsoft.com/en-us/sql/relational-databases/indexes/tune-nonclustered-missing-index-suggestions

SELECT
 mid.equality_columns     AS Equality_Columns,
 mid.inequality_columns   AS Inequality_Columns,
 mid.included_columns     AS Included_Columns,
 migs.user_seeks          AS User_Seeks,
 migs.avg_total_user_cost AS Avg_Total_User_Cost,
 migs.avg_user_impact     AS Avg_User_Impact_Percent
FROM
 sys.dm_db_missing_index_details                mid
 INNER JOIN sys.dm_db_missing_index_groups      mig
  ON mig.index_handle = mid.index_handle
 INNER JOIN sys.dm_db_missing_index_group_stats migs
  ON migs.group_handle = mig.index_group_handle
WHERE mid.database_id = DB_ID()
      AND mid.object_id = OBJECT_ID('dbo.FactSalesCompressed')
ORDER BY migs.avg_user_impact DESC;
GO

-- Paul White: The Eager Index Spool and The Optimizer
-- https://sqlperformance.com/2019/11/sql-performance/eager-index-spool-optimizer

-- Review the original query

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

-- Proposed covering index (do not execute yet)
/*
CREATE NONCLUSTERED INDEX IX_FactSalesCompressed_StoreKey_OrderDate
 ON dbo.FactSalesCompressed (StoreKey, OrderDate)
 INCLUDE (SalesAmount);
*/

-- Test the window function with the supporting index

SET STATISTICS IO, TIME, XML ON;
GO

DECLARE @StoreKey int = 1;
DECLARE @StartDate date = '20260101';
DECLARE @EndDate date = '20260401';

SELECT
 f.OrderDate,
 SUM(f.SalesAmount)                                                           AS DailySales,
 SUM(SUM(f.SalesAmount)) OVER (ORDER BY f.OrderDate ROWS UNBOUNDED PRECEDING) AS RunningTotalSales
FROM
 dbo.FactSalesCompressed f
WHERE f.StoreKey = @StoreKey
      AND f.OrderDate >= @StartDate
      AND f.OrderDate < @EndDate
GROUP BY f.OrderDate
ORDER BY f.OrderDate;

SET STATISTICS IO, TIME, XML OFF;
GO

-- MSSQLTips: Calculate a Moving Average with T-SQL Windowing Functions
-- https://www.mssqltips.com/sqlservertip/8124/calculate-a-moving-average-with-t-sql-windowing-functions/

-- Create the supporting index

DROP INDEX IF EXISTS IX_FactSalesCompressed_StoreKey_OrderDate
 ON dbo.FactSalesCompressed;
GO

CREATE NONCLUSTERED INDEX IX_FactSalesCompressed_StoreKey_OrderDate
 ON dbo.FactSalesCompressed (StoreKey, OrderDate)
 INCLUDE (SalesAmount);
GO

-- Rerun the same query and compare reads, CPU, and elapsed time
SET STATISTICS IO, TIME, XML ON;
GO

DECLARE @StoreKey int = 1;
DECLARE @StartDate date = '20260101';
DECLARE @EndDate date = '20260401';

SELECT
 f.OrderDate,
 SUM(f.SalesAmount)                                                           AS DailySales,
 SUM(SUM(f.SalesAmount)) OVER (ORDER BY f.OrderDate ROWS UNBOUNDED PRECEDING) AS RunningTotalSales
FROM
 dbo.FactSalesCompressed f
WHERE f.StoreKey = @StoreKey
      AND f.OrderDate >= @StartDate
      AND f.OrderDate < @EndDate
GROUP BY f.OrderDate
ORDER BY f.OrderDate;

SET STATISTICS IO, TIME, XML OFF;
GO

-- Should we keep the index?