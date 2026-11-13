/* =============================================================
   File: demo_03_blocking.sql
   Demo 03: Reduce blocking in a warehouse
   Module 04: Monitor and optimize warehouse workloads

   Download the demo files for this course from the following link:
   https://github.com/JaredWestover/sql-server-data-warehouse-performance
============================================================= */

USE DataWarehouseDemo;
GO

-- Check the current isolation level and row versioning settings
SELECT
 CASE transaction_isolation_level
  WHEN 0 THEN 'Unspecified'
  WHEN 1 THEN 'Read Uncommitted'
  WHEN 2 THEN 'Read Committed'
  WHEN 3 THEN 'Repeatable Read'
  WHEN 4 THEN 'Serializable'
  WHEN 5 THEN 'Snapshot'
  ELSE 'Unknown' END AS TransactionIsolationLevel
FROM
 sys.dm_exec_sessions
WHERE session_id = @@SPID;

SELECT
 name,
 is_read_committed_snapshot_on
FROM
 sys.databases
WHERE name = DB_NAME();
GO

-- Start a blocking transaction. Keep this session open so its locks stay held.
BEGIN TRANSACTION;

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
 TOP (10)
 fs.SalesKey,
 fs.OrderNumber,
 fs.PurchaseOrderNumber,
 fs.OrderRiskCategory,
 fs.OrderDate,
 fs.CustomerKey,
 fs.ProductKey,
 fs.StoreKey,
 fs.PromotionKey,
 fs.Quantity,
 fs.SalesAmount,
 fs.DiscountAmount
FROM
 dbo.FactSalesCompressed AS fs;
GO

ROLLBACK TRANSACTION;
GO

ALTER DATABASE DataWarehouseDemo
 SET
  READ_COMMITTED_SNAPSHOT ON;
GO

-- Optional cleanup. Run only after you're finished with the course.
USE [master];
GO

IF DB_ID('DataWarehouseDemo') IS NOT NULL
BEGIN
 ALTER DATABASE DataWarehouseDemo
  SET
   SINGLE_USER
  WITH ROLLBACK IMMEDIATE;

 DROP DATABASE DataWarehouseDemo;
END;
GO