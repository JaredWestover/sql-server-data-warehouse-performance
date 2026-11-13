/* =============================================================
   File: demo_03_concurrency.sql
   Demo 03: Reduce blocking in a warehouse
   Module 04: Monitor and optimize warehouse workloads

   Download the demo files for this course from the following link:
   https://github.com/JaredWestover/sql-server-data-warehouse-performance
============================================================= */

USE DataWarehouseDemo;
GO

SELECT TOP 10 * FROM dbo.FactSalesCompressed;
GO


-- Summarize locks by type, mode, and status
SELECT
 OBJECT_NAME(resource_associated_entity_id) AS table_name,
 resource_type,
 request_mode,
 request_status,
 COUNT(*)                                   AS lock_count
FROM
 sys.dm_tran_locks
WHERE resource_database_id = DB_ID()
GROUP BY resource_associated_entity_id,
         resource_type,
         request_mode,
         request_status;
GO


-- NOLOCK (READ UNCOMMITTED) can return uncommitted rows that may later be rolled back
SELECT TOP 10 * FROM dbo.FactSalesCompressed WITH (NOLOCK);
GO

-- Allow dirty reads for this session.
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
GO

SELECT TOP 10 * FROM dbo.FactSalesCompressed;
GO

-- Restore Read Committed and verify the session setting.
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
GO

DBCC USEROPTIONS;
GO