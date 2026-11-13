/* =============================================================
   Demo 02: Manage columnstore health
   Module 02: Optimize warehouses with columnstore indexes

   Download the demo files for this course from the following link:
   https://github.com/JaredWestover/sql-server-data-warehouse-performance
============================================================= */

USE DataWarehouseDemo;
GO

-- Establish the performance baseline
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
WHERE OrderDate >= '20260101'
      AND OrderDate < '20260401'
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
 SQL Server Execution Times:
   CPU time = 296 ms,  elapsed time = 81 ms.
*/

-- Review the initial columnstore rowgroups
SELECT
 rg.row_group_id     AS Rowgroup_Id,
 rg.state_desc       AS State_Description,
 rg.total_rows       AS Total_Rows,
 rg.deleted_rows     AS Deleted_Rows,
 CAST
 (
  rg.deleted_rows * 100.0 /
  NULLIF(rg.total_rows, 0)
  AS decimal(5, 2)
 )                   AS Deleted_Row_Percent,
 rg.trim_reason_desc AS Trim_Reason
FROM
 sys.indexes                                                i
 INNER JOIN sys.dm_db_column_store_row_group_physical_stats rg
  ON i.object_id = rg.object_id
     AND i.index_id = rg.index_id
WHERE i.object_id = OBJECT_ID('dbo.FactSalesColumnstore')
ORDER BY rg.row_group_id;
GO

-- Review the column segments for OrderDate
SELECT
 OBJECT_NAME(i.object_id) AS Table_Name,
 i.name                   AS Index_Name,
 c.name                   AS Column_Name,
 se.segment_id            AS Rowgroup_Id,
 se.row_count             AS Segment_Row_Count,
 DATEADD
 (
  DAY,
  CONVERT(int, se.min_data_id),
  DATEFROMPARTS(1, 1, 1)
 )                        AS Minimum_OrderDate,
 DATEADD
 (
  DAY,
  CONVERT(int, se.max_data_id),
  DATEFROMPARTS(1, 1, 1)
 )                        AS Maximum_OrderDate
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

-- Update approximately 3 million rows
-- The old versions are marked as deleted and the new versions
-- are inserted into delta rowgroups.
UPDATE
 dbo.FactSalesColumnstore
SET
 OrderRiskCategory = 'Reviewed'
WHERE OrderDate >= '20260101'
      AND OrderDate < '20260401';
GO

-- Review the affected rowgroups after the update
SELECT
 rg.row_group_id     AS Rowgroup_Id,
 rg.state_desc       AS State_Description,
 rg.total_rows       AS Total_Rows,
 rg.deleted_rows     AS Deleted_Rows,
 CAST
 (
  rg.deleted_rows * 100.0 /
  NULLIF(rg.total_rows, 0)
  AS decimal(5, 2)
 )                   AS Deleted_Row_Percent,
 rg.trim_reason_desc AS Trim_Reason
FROM
 sys.indexes                                                i
 INNER JOIN sys.dm_db_column_store_row_group_physical_stats rg
  ON i.object_id = rg.object_id
     AND i.index_id = rg.index_id
WHERE i.object_id = OBJECT_ID('dbo.FactSalesColumnstore')
      AND
      (
       rg.deleted_rows > 0
       OR rg.state_desc <> 'COMPRESSED'
      )
ORDER BY rg.row_group_id;
GO

-- Rerun the reporting query after the update
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
WHERE OrderDate >= '20260101'
      AND OrderDate < '20260401'
GROUP BY YEAR(OrderDate),
         MONTH(OrderDate),
         StoreKey
ORDER BY SalesYear,
         SalesMonth,
         StoreKey;
GO

SET STATISTICS IO, TIME OFF;
GO

-- Compress delta rowgroups and clean up qualifying rowgroups
ALTER INDEX CCI_FactSalesColumnstore
 ON dbo.FactSalesColumnstore
 REORGANIZE
 WITH (COMPRESS_ALL_ROW_GROUPS = ON);
GO

-- Review the affected rowgroups after reorganizing the index
SELECT
 rg.row_group_id     AS Rowgroup_Id,
 rg.state_desc       AS State_Description,
 rg.total_rows       AS Total_Rows,
 rg.deleted_rows     AS Deleted_Rows,
 CAST
 (
  rg.deleted_rows * 100.0 /
  NULLIF(rg.total_rows, 0)
  AS decimal(5, 2)
 )                   AS Deleted_Row_Percent,
 rg.trim_reason_desc AS Trim_Reason
FROM
 sys.indexes                                                i
 INNER JOIN sys.dm_db_column_store_row_group_physical_stats rg
  ON i.object_id = rg.object_id
     AND i.index_id = rg.index_id
WHERE i.object_id = OBJECT_ID('dbo.FactSalesColumnstore')
      AND
      (
       rg.deleted_rows > 0
       OR rg.state_desc <> 'COMPRESSED'
       OR rg.trim_reason_desc = 'REORG'
      )
ORDER BY rg.row_group_id;
GO

-- Rerun the reporting query after reorganizing the index
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
WHERE OrderDate >= '20260101'
      AND OrderDate < '20260401'
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
A rebuild performs a more complete cleanup but requires more time,
CPU, memory, transaction log space, and storage resources.

ALTER INDEX CCI_FactSalesColumnstore
 ON dbo.FactSalesColumnstore
 REBUILD;
GO
*/