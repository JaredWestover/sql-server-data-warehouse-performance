/* =============================================================
   Demo 03: Validate partition elimination
   Module 01: Optimize tables for warehouse performance

   Download the demo files for this course from the following link:
   https://github.com/JaredWestover/sql-server-data-warehouse-performance
============================================================= */

USE DataWarehouseDemo;
GO

DROP TABLE IF EXISTS dbo.FactSales;
GO

CREATE TABLE dbo.FactSales
(
 SalesKey       int            NOT NULL,
 OrderDate      date           NOT NULL,
 CustomerKey    int            NOT NULL,
 ProductKey     int            NOT NULL,
 StoreKey       int            NOT NULL,
 PromotionKey   int            NOT NULL,
 Quantity       tinyint        NOT NULL,
 SalesAmount    decimal(10, 2) NOT NULL,
 DiscountAmount decimal(10, 2) NOT NULL
);

INSERT INTO dbo.FactSales WITH (TABLOCK)
(
 SalesKey,
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
 value,
 DATEADD(DAY, (value - 1) % 2922, CONVERT(date, '20190101')),
 1 + (value % 2000000),
 1 + (value % 10000),
 1 + (value % 100),
 1 + (value % 50),
 1 + (value % 5),
 CAST(10 + ((value % 50000) / 100.0) AS decimal(10, 2)),
 CAST((value % 1000) / 100.0 AS decimal(10, 2))
FROM
 GENERATE_SERIES(1, 10000000);

-- Create a clustered index on OrderDate and SalesKey
CREATE CLUSTERED INDEX CX_FactSales_OrderDate
 ON dbo.FactSales (OrderDate, SalesKey);
GO

-- Check the space used by the table
SELECT
 OBJECT_NAME(ps.object_id)                                          AS Table_Name,
 SUM(ps.reserved_page_count) * 8 / 1024.0                           AS Reserved_MB,
 SUM(ps.used_page_count) * 8 / 1024.0                               AS Used_MB,
 (SUM(ps.reserved_page_count) - SUM(ps.used_page_count)) * 8 / 1024 AS Unused_MB,
 SUM(ps.used_page_count)                                            AS Used_Page_Count
FROM
 sys.dm_db_partition_stats ps
WHERE ps.object_id = OBJECT_ID('dbo.FactSales')
GROUP BY ps.object_id;

-- Below is a typical query the business might run on a regular basis
SET STATISTICS IO, TIME ON;
GO

SELECT
 ProductKey,
 SUM(SalesAmount) AS TotalSales,
 SUM(Quantity)    AS TotalQuantity,
 COUNT_BIG(*)     AS SalesCount
FROM
 dbo.FactSales
WHERE OrderDate >= '20250101'
      AND OrderDate < '20260101'
GROUP BY ProductKey;
GO

SET STATISTICS IO, TIME OFF;
GO

/*
 SQL Server Execution Times:
   CPU time = 60 ms, elapsed time = 27 ms.

 SqlQueryStress (https://github.com/erikej/sqlquerystress)
 - 10 threads x 100 iterations: 21 seconds elapsed

 1 Billion Rows Test (50GB)
 - 10 SqlQueryStress iterations: 19 seconds
*/

/* Drop existing partition scheme/function before recreating (uncomment if re-running this script)
DROP PARTITION SCHEME ps_FactSales_OrderDate;
GO
DROP PARTITION FUNCTION pf_FactSales_OrderDate;
GO
*/

-- Create the partition function

CREATE PARTITION FUNCTION pf_FactSales_OrderDate (date)
 AS RANGE RIGHT FOR VALUES
 (
 '20200101',
 '20210101',
 '20220101',
 '20230101',
 '20240101',
 '20250101',
 '20260101',
 '20270101');
GO

-- Create the partition scheme
CREATE PARTITION SCHEME ps_FactSales_OrderDate
 AS PARTITION pf_FactSales_OrderDate
 ALL TO ([PRIMARY]);
GO

-- Partition the existing table by OrderDate
CREATE CLUSTERED INDEX CX_FactSales_OrderDate
 ON dbo.FactSales (OrderDate, SalesKey)
 WITH (DROP_EXISTING = ON)
 ON ps_FactSales_OrderDate(OrderDate);
GO

-- Review the partitions
SELECT
 p.partition_number,
 prv.value AS Boundary_Value,
 p.rows
FROM
 sys.partitions                       p
 LEFT JOIN sys.partition_range_values prv
  ON prv.function_id =
   (SELECT
     TOP 1
     function_id
    FROM
     sys.partition_functions
    WHERE name = 'pf_FactSales_OrderDate')
     AND prv.boundary_id = p.partition_number - 1
WHERE p.object_id = OBJECT_ID('dbo.FactSales')
      AND p.index_id = 1
ORDER BY p.partition_number;
GO

-- Re-run the same query to verify partition elimination
SET STATISTICS IO, TIME ON;
GO

SELECT
 ProductKey,
 SUM(SalesAmount) AS TotalSales,
 SUM(Quantity)    AS TotalQuantity,
 COUNT_BIG(*)     AS SalesCount
FROM
 dbo.FactSales
WHERE OrderDate >= '20250101'
      AND OrderDate < '20260101'
GROUP BY ProductKey;

-- OPTION (RECOMPILE, MAXDOP 1, USE HINT ('DISALLOW_BATCH_MODE'));
SET STATISTICS IO, TIME OFF;
GO

/*
 SQL Server Execution Times:
   CPU time = 78 ms, elapsed time = 25 ms.

 SqlQueryStress
 - 1,000 iterations: 22 seconds elapsed, 22ms per iteration

 1 Billion Rows Test (50GB)
 - 10 SqlQueryStress iterations: 18 seconds
*/

-- Reference
-- SQL Server Table Partitioning
-- https://www.brentozar.com/sql/table-partitioning-resources/