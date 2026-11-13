/* =============================================================
   Demo 01: Improve analytical queries with columnstore
   Module 02: Optimize warehouses with columnstore indexes

   Download the demo files for this course from the following link:
   https://github.com/JaredWestover/sql-server-data-warehouse-performance
============================================================= */

USE DataWarehouseDemo;
GO

-- Drop the demo tables if they already exist
DROP TABLE IF EXISTS dbo.LoadingFactSales;
DROP TABLE IF EXISTS dbo.FactSalesCompressed;
DROP TABLE IF EXISTS dbo.FactSalesColumnstore;
GO

-- Create a loading table that will serve as the source
-- for both versions of the fact table
CREATE TABLE dbo.LoadingFactSales
(
 SalesKey            int            NOT NULL,
 OrderNumber         varchar(20)    NOT NULL,
 PurchaseOrderNumber varchar(30)    NOT NULL,
 OrderRiskCategory   varchar(20)    NOT NULL,
 OrderDate           date           NOT NULL,
 CustomerKey         int            NOT NULL,
 ProductKey          int            NOT NULL,
 StoreKey            int            NOT NULL,
 PromotionKey        int            NOT NULL,
 Quantity            tinyint        NOT NULL,
 SalesAmount         decimal(10, 2) NOT NULL,
 DiscountAmount      decimal(10, 2) NOT NULL
) ON [PRIMARY];
GO

-- Load 100 million rows into the loading table
INSERT INTO dbo.LoadingFactSales WITH (TABLOCK)
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
 value,
 CONCAT('ORD-', value),
 CONCAT('PO-', value),
 CASE value % 6
  WHEN 0 THEN 'Low'
  WHEN 1 THEN 'Medium'
  WHEN 2 THEN 'High'
  WHEN 3 THEN 'Critical'
  WHEN 4 THEN 'Under Review'
  WHEN 5 THEN 'Not Scored' END,
 DATEADD(DAY, (value - 1) % 2922, CONVERT(date, '20190101')),
 1 + (value % 2000000),
 1 + (value % 10000),
 1 + (value % 100),
 1 + (value % 50),
 1 + (value % 5),
 CAST(10 + ((value % 50000) / 100.0) AS decimal(10, 2)),
 CAST((value % 1000) / 100.0 AS decimal(10, 2))
FROM
 GENERATE_SERIES(1, 100000000);
GO

CREATE CLUSTERED INDEX CX_LoadingFactSales_SalesKey
 ON dbo.LoadingFactSales (SalesKey)
 WITH (DATA_COMPRESSION = PAGE)
 ON [PRIMARY];
GO


-- Create the rowstore version from the loading table
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
 dbo.FactSalesCompressed
ON [PRIMARY]
FROM
 dbo.LoadingFactSales;
GO

-- Create a PAGE-compressed clustered rowstore index
CREATE CLUSTERED INDEX CX_FactSalesCompressed_OrderDate
 ON dbo.FactSalesCompressed (OrderDate, SalesKey)
 WITH (DATA_COMPRESSION = PAGE)
 ON [PRIMARY];
GO

-- Check the space used by the compressed rowstore table
SELECT
 OBJECT_NAME(ps.object_id)                                            AS Table_Name,
 SUM(ps.reserved_page_count) * 8 / 1024.0                             AS Reserved_MB,
 SUM(ps.used_page_count) * 8 / 1024.0                                 AS Used_MB,
 (SUM(ps.reserved_page_count) - SUM(ps.used_page_count)) * 8 / 1024.0 AS Unused_MB,
 SUM(ps.used_page_count)                                              AS Used_Page_Count
FROM
 sys.dm_db_partition_stats ps
WHERE ps.object_id = OBJECT_ID('dbo.FactSalesCompressed')
GROUP BY ps.object_id;
GO

-- Run the reporting query against the compressed rowstore table
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
 dbo.FactSalesCompressed
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
-- Instead of creating a second table, you could convert the
-- PAGE-compressed rowstore table directly to columnstore.
-- DROP_EXISTING replaces the clustered rowstore index while
-- leaving the data in the table.

CREATE CLUSTERED COLUMNSTORE INDEX CX_FactSalesCompressed_OrderDate
 ON dbo.FactSalesCompressed
 WITH (DROP_EXISTING = ON)
 ON [PRIMARY];
GO
*/

-- Create the columnstore version from the same loading table
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
 dbo.FactSalesColumnstore
ON [PRIMARY]
FROM
 dbo.LoadingFactSales;
GO

-- Create a clustered columnstore index on the second table
CREATE CLUSTERED COLUMNSTORE INDEX CCI_FactSalesColumnstore
 ON dbo.FactSalesColumnstore
 ON [PRIMARY];
GO

-- Compare storage for the two versions of the fact table
SELECT
 OBJECT_NAME(ps.object_id)                                            AS Table_Name,
 p.data_compression_desc                                              AS Compression_Type,
 SUM(ps.row_count)                                                    AS Row_Count,
 SUM(ps.reserved_page_count) * 8 / 1024.0                             AS Reserved_MB,
 SUM(ps.used_page_count) * 8 / 1024.0                                 AS Used_MB,
 (SUM(ps.reserved_page_count) - SUM(ps.used_page_count)) * 8 / 1024.0 AS Unused_MB,
 SUM(ps.used_page_count)                                              AS Used_Page_Count
FROM
 sys.dm_db_partition_stats ps
 INNER JOIN sys.partitions p
  ON p.partition_id = ps.partition_id
WHERE ps.object_id IN ( OBJECT_ID('dbo.FactSalesCompressed'),
                        OBJECT_ID('dbo.FactSalesColumnstore'))
      AND ps.index_id = 1
GROUP BY ps.object_id,
         p.data_compression_desc
ORDER BY Table_Name;
GO

-- Run the same reporting query against the columnstore table
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