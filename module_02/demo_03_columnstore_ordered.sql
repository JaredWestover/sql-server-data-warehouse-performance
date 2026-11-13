/* =============================================================
   Demo 03: Improve segment elimination with ordered columnstore
   Module 02: Optimize warehouses with columnstore indexes

   Download the demo files for this course from the following link:
   https://github.com/JaredWestover/sql-server-data-warehouse-performance
============================================================= */

USE DataWarehouseDemo;
GO

SET STATISTICS IO, TIME ON;
GO

SELECT
 YEAR(OrderDate)                   AS SalesYear,
 MONTH(OrderDate)                  AS SalesMonth,
 StoreKey,
 COUNT_BIG(*)                      AS SalesCount,
 SUM(SalesAmount)                  AS TotalSales,
 SUM(DiscountAmount)               AS TotalDiscounts,
 SUM(SalesAmount - DiscountAmount) AS NetSales,
 SUM(CAST(Quantity AS bigint))     AS TotalQuantity,
 AVG(SalesAmount)                  AS AverageSaleAmount,
 MIN(SalesAmount)                  AS MinimumSaleAmount,
 MAX(SalesAmount)                  AS MaximumSaleAmount
FROM
 dbo.FactSalesColumnstore
WHERE OrderDate >= '20250101'
      AND OrderDate < '20270101'
GROUP BY YEAR(OrderDate),
         MONTH(OrderDate),
         StoreKey
ORDER BY SalesYear,
         SalesMonth,
         StoreKey;
GO

SET STATISTICS IO, TIME OFF;
GO

-- Review the column segments for OrderDate
SELECT
 OBJECT_NAME(i.object_id)                                           AS Table_Name,
 i.name                                                             AS Index_Name,
 c.name                                                             AS Column_Name,
 se.segment_id                                                      AS Rowgroup_Id,
 se.row_count                                                       AS Segment_Row_Count,
 DATEADD(DAY, CONVERT(int, se.min_data_id), DATEFROMPARTS(1, 1, 1)) AS Minimum_OrderDate,
 DATEADD(DAY, CONVERT(int, se.max_data_id), DATEFROMPARTS(1, 1, 1)) AS Maximum_OrderDate
FROM
 sys.column_store_segments se
 INNER JOIN sys.partitions p
  ON p.hobt_id = se.hobt_id
 INNER JOIN sys.indexes    i
  ON i.object_id = p.object_id
     AND i.index_id = p.index_id
 INNER JOIN sys.columns    c
  ON c.object_id = p.object_id
     AND c.column_id = se.column_id
WHERE i.object_id = OBJECT_ID('dbo.FactSalesColumnstore')
      AND c.name = 'OrderDate'
ORDER BY se.segment_id;
GO

DROP TABLE IF EXISTS dbo.FactSalesColumnstoreOrdered;
GO

SELECT
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
INTO
 dbo.FactSalesColumnstoreOrdered
ON [PRIMARY]
FROM
 dbo.LoadingFactSales;
GO

-- This statement took about 6 minutes
CREATE CLUSTERED COLUMNSTORE INDEX CCI_FactSalesColumnstoreOrdered
 ON dbo.FactSalesColumnstoreOrdered ORDER(OrderDate)
 WITH (MAXDOP = 1);
GO

-- Review the column segments for OrderDate
SELECT
 OBJECT_NAME(i.object_id)                                           AS Table_Name,
 i.name                                                             AS Index_Name,
 c.name                                                             AS Column_Name,
 se.segment_id                                                      AS Rowgroup_Id,
 se.row_count                                                       AS Segment_Row_Count,
 DATEADD(DAY, CONVERT(int, se.min_data_id), DATEFROMPARTS(1, 1, 1)) AS Minimum_OrderDate,
 DATEADD(DAY, CONVERT(int, se.max_data_id), DATEFROMPARTS(1, 1, 1)) AS Maximum_OrderDate
FROM
 sys.column_store_segments se
 INNER JOIN sys.partitions p
  ON p.hobt_id = se.hobt_id
 INNER JOIN sys.indexes    i
  ON i.object_id = p.object_id
     AND i.index_id = p.index_id
 INNER JOIN sys.columns    c
  ON c.object_id = p.object_id
     AND c.column_id = se.column_id
WHERE i.object_id = OBJECT_ID('dbo.FactSalesColumnstoreOrdered')
      AND c.name = 'OrderDate'
ORDER BY se.segment_id;
GO

SET STATISTICS IO, TIME ON;
GO

SELECT
 YEAR(OrderDate)                   AS SalesYear,
 MONTH(OrderDate)                  AS SalesMonth,
 StoreKey,
 COUNT_BIG(*)                      AS SalesCount,
 SUM(SalesAmount)                  AS TotalSales,
 SUM(DiscountAmount)               AS TotalDiscounts,
 SUM(SalesAmount - DiscountAmount) AS NetSales,
 SUM(CAST(Quantity AS bigint))     AS TotalQuantity,
 AVG(SalesAmount)                  AS AverageSaleAmount,
 MIN(SalesAmount)                  AS MinimumSaleAmount,
 MAX(SalesAmount)                  AS MaximumSaleAmount
FROM
 dbo.FactSalesColumnstoreOrdered
WHERE OrderDate >= '20250101'
      AND OrderDate < '20270101'
GROUP BY YEAR(OrderDate),
         MONTH(OrderDate),
         StoreKey
ORDER BY SalesYear,
         SalesMonth,
         StoreKey;
GO

SET STATISTICS IO, TIME OFF;
GO

/*
Approximately 20% less CPU time on average with the ordered columnstore index.

SQL Server also reads fewer unnecessary segments, allowing the
buffer pool to hold more of the data the workload needs.
*/

SELECT
 COUNT(1)
FROM
 (SELECT
   TOP (10000000)
   *
  FROM
   dbo.LoadingFactSales
  ORDER BY SalesKey ASC) AS CacheWarmup;

SET STATISTICS TIME ON;
GO

-- Load the nonordered columnstore index
INSERT INTO dbo.FactSalesColumnstore WITH (TABLOCK)
SELECT TOP (10000000) * FROM dbo.LoadingFactSales ORDER BY SalesKey ASC;
GO

-- Load the ordered columnstore index
INSERT INTO dbo.FactSalesColumnstoreOrdered WITH (TABLOCK)
SELECT TOP (10000000) * FROM dbo.LoadingFactSales ORDER BY SalesKey ASC;
GO

SET STATISTICS TIME OFF;
GO

-- Performance tuning with ordered columnstore indexes
-- https://learn.microsoft.com/en-us/sql/relational-databases/indexes/ordered-columnstore-indexes

-- Columnstore indexes: overview
-- https://learn.microsoft.com/en-us/sql/relational-databases/indexes/columnstore-indexes-overview