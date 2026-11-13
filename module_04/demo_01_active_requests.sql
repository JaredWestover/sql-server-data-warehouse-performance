/* =============================================================
   Demo 01: Analyze warehouse workloads
   Module 04: Monitor and optimize warehouse workloads

   Download the demo files for this course from the following link:
   https://github.com/JaredWestover/sql-server-data-warehouse-performance
============================================================= */

USE DataWarehouseDemo;
GO

-- Inspect current requests in this database
SELECT
 r.session_id,
 r.status,
 r.wait_resource,
 r.command,
 r.total_elapsed_time AS elapsed_time_ms,
 r.cpu_time           AS cpu_time_ms,
 qp.query_plan,
 t.text               AS sql_text
FROM
 sys.dm_exec_requests                           AS r
 CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
 CROSS APPLY sys.dm_exec_query_plan(r.plan_handle) AS qp
WHERE r.database_id = DB_ID()
      AND r.session_id <> @@SPID;
GO

-- Microsoft Learn: sys.dm_exec_requests (Transact-SQL)
-- https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-objects/sys-dm-exec-requests-transact-sql?view=sql-server-ver17

-- Which requests have or are waiting for memory grants?

SELECT
 mg.session_id,
 mg.requested_memory_kb / 1024.0 AS requested_memory_mb,
 mg.granted_memory_kb / 1024.0   AS granted_memory_mb,
 mg.used_memory_kb / 1024.0      AS used_memory_mb,
 t.text                          AS sql_text
FROM
 sys.dm_exec_query_memory_grants                 AS mg
 CROSS APPLY sys.dm_exec_sql_text(mg.sql_handle) AS t
WHERE mg.session_id <> @@SPID;
GO

-- Last resort: kill the session. Replace 00 with the target session_id.
-- DECLARE @SessionId int = 00;
-- DECLARE @KillCommand nvarchar(20) = CONCAT(N'KILL ', @SessionId);

-- EXEC sys.sp_executesql
--  @KillCommand;
-- GO

-- Block future executions of this query (SQL Server 2025+)
EXECUTE sys.sp_query_store_set_hints
 @query_id = 3,
 @query_hints = N'OPTION (USE HINT (''ABORT_QUERY_EXECUTION''))';
GO

-- Remove the Query Store hints to allow execution again
EXECUTE sys.sp_query_store_clear_hints
 @query_id = 3;