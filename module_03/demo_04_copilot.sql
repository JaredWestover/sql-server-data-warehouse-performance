/* =============================================================
   Demo 04: Validate AI query tuning suggestions
   Module 03: Diagnose and tune warehouse queries

   Download the demo files for this course from the following link:
   https://github.com/JaredWestover/sql-server-data-warehouse-performance
============================================================= */

/* =============================================================
   Setup: GitHub Copilot in SQL Server Management Studio 22
   (Complete before running this demo)

   1. Confirm you have a GitHub account with Copilot access
      (Free, Pro, Business, or Enterprise, or a seat assigned by your org).
      Plans: https://github.com/features/copilot/plans
   2. Add the AI Assistance workload: open the Visual Studio Installer,
      select your SSMS installation, select Modify, check
      AI Assistance on the Workloads tab, then select Modify again.
   3. Sign in: in SSMS, select the GitHub Copilot status icon in the upper-right
      corner, then select Open Chat Window to Sign In (or Add another account).
      Sign in with a GitHub account that has an active Copilot subscription, or
      select Sign up for Copilot Free.
   4. Confirm the Copilot status icon shows active and the chat window responds
      to a simple prompt.
   5. If Copilot is disabled for your account, contact your IT administrator.

   Docs: https://learn.microsoft.com/en-us/ssms/github-copilot/installation-state
============================================================= */

-- Model Claude Haiku 5.5 provides a balanced level of intelligence

-- Prompt 1: How large is the DataWarehouseDemo database? Provide a list of all tables, including their row counts and storage sizes in MB. Sort the results by table size, largest to smallest.

USE DataWarehouseDemo;
GO
-- Insert Copilot-generated table size query here
-- Created by GitHub Copilot in SSMS - review carefully before executing
-- Part 1: Total database size in MB (data and log files)
SELECT
    DB_NAME() AS DatabaseName,
    CAST(SUM(size) * 8.0 / 1024 AS DECIMAL(18, 2)) AS TotalSizeMB
FROM sys.database_files;

-- Part 2: Row count and storage size in MB for each user table, largest first
SELECT
    SCHEMA_NAME(t.schema_id) AS SchemaName,
    t.name AS TableName,
    SUM(CASE WHEN ps.index_id IN (0, 1) THEN ps.row_count ELSE 0 END) AS TotalRows,
    CAST(SUM(ps.reserved_page_count) * 8.0 / 1024 AS DECIMAL(18, 2)) AS TotalSizeMB,
    CAST(SUM(ps.used_page_count) * 8.0 / 1024 AS DECIMAL(18, 2)) AS UsedSizeMB
FROM sys.tables AS t
JOIN sys.dm_db_partition_stats AS ps
    ON t.object_id = ps.object_id
WHERE t.is_ms_shipped = 0
  AND t.is_dropped_ledger_table = 0
GROUP BY t.schema_id, t.name
ORDER BY TotalSizeMB DESC, TotalRows DESC;


-- Prompt 2: You are an experienced SQL Server DBA. Review the following query and recommend ways to improve its performance. The original query took about 2 minutes to run, but the business needs it to run in under 2 seconds. Suggest query rewrites or indexes that could help meet this goal, and explain why. Check existing indexes before recommending new ones.

SET STATISTICS IO, TIME ON;
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

-- Insert Copilot's rewritten query here
DECLARE @StoreKey int = 1;
DECLARE @StartDate date = '20260101';
DECLARE @EndDate date = '20260401';

SELECT
    d.OrderDate,
    d.DailySales,
    SUM(d.DailySales) OVER (ORDER BY d.OrderDate ROWS UNBOUNDED PRECEDING) AS RunningTotalSales
FROM
(
    SELECT
        f.OrderDate,
        SUM(f.SalesAmount) AS DailySales
    FROM dbo.FactSalesCompressed AS f
    WHERE f.StoreKey = @StoreKey
      AND f.OrderDate >= @StartDate
      AND f.OrderDate < @EndDate
    GROUP BY f.OrderDate
) AS d
ORDER BY d.OrderDate;

SET STATISTICS IO, TIME OFF;
GO