/* =============================================================
   Demo 02: Configure SQL Server for warehouses
   Module 04: Monitor and optimize warehouse workloads

   Download the demo files for this course from the following link:
   https://github.com/JaredWestover/sql-server-data-warehouse-performance
============================================================= */

USE DataWarehouseDemo;
GO

/*
Setting 1: Maximum and Minimum Server Memory
*/

-- Microsoft Learn: Server memory configuration options
-- https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/server-memory-server-configuration-options?view=sql-server-ver17

-- Erik Darling: Setting Min Server Memory and Max Server Memory
-- https://erikdarling.com/setting-min-server-memory-and-max-server-memory/

SELECT
 x.name,
 x.value_gb,
 x.value_in_use_gb,
 x.total_physical_memory_gb,
 (x.value_in_use_gb / x.total_physical_memory_gb) * 100 AS percent_of_total_memory
FROM
 (SELECT
   c.name,
   CONVERT(bigint, c.value) / 1024        AS value_gb,
   CONVERT(bigint, c.value_in_use) / 1024 AS value_in_use_gb,
   dosm.total_physical_memory_gb
  FROM
   sys.configurations               AS c
   CROSS JOIN
    (SELECT
      CEILING(dosm.total_physical_memory_kb / 1024. / 1024.) AS total_physical_memory_gb
     FROM
      sys.dm_os_sys_memory AS dosm) dosm
  WHERE c.name IN ( N'min server memory (MB)', N'max server memory (MB)' )) AS x;
GO

/*
Setting 2: Cost Threshold for Parallelism (CTFP)
*/

SELECT
 name,
 value,
 value_in_use
FROM
 sys.configurations
WHERE name IN ( 'cost threshold for parallelism',
                'max degree of parallelism' );
GO

-- Microsoft Learn: Server configuration: cost threshold for parallelism
-- https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/configure-the-cost-threshold-for-parallelism-server-configuration-option?view=sql-server-ver17

-- MSSQLTips: Limit Cost Threshold for Parallelism for Small SQL Queries
-- https://www.mssqltips.com/sqlservertip/8119/limit-cost-threshold-for-parallelism-for-small-sql-queries/