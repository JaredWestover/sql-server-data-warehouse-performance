/* =============================================================
   Demo 02: Reduce warehouse storage with data compression
   Module 01: Optimize tables for warehouse performance

   Download the demo files for this course from the following link:
   https://github.com/JaredWestover/sql-server-data-warehouse-performance
============================================================= */

USE DataWarehouseDemo;
GO


-- Clean up any existing tables
DROP TABLE IF EXISTS dbo.DimCustomers;
DROP TABLE IF EXISTS dbo.DimCustomersCompressed;
GO


-- Create a copy of the optimized table
SELECT * INTO dbo.DimCustomersCompressed FROM dbo.DimCustomersOptimized;
GO


-- Add the clustered primary key
ALTER TABLE dbo.DimCustomersCompressed
ADD
 CONSTRAINT PK_DimCustomersCompressed
 PRIMARY KEY CLUSTERED (CustomerKey)
 WITH(FILLFACTOR = 100);
GO


-- Rebuild the optimized table with consistent index structure
ALTER INDEX PK_DimCustomersOptimized
 ON dbo.DimCustomersOptimized
 REBUILD
 WITH (FILLFACTOR = 100);
GO


-- Rebuild the compressed table for comparison
ALTER INDEX PK_DimCustomersCompressed
 ON dbo.DimCustomersCompressed
 REBUILD
 WITH (FILLFACTOR = 100);
GO


-- Verify both tables have the same structure before compression testing
SELECT
 OBJECT_NAME(ps.object_id)                                          AS Table_Name,
 SUM(ps.reserved_page_count) * 8 / 1024.0                           AS Reserved_MB,
 SUM(ps.used_page_count) * 8 / 1024.0                               AS Used_MB,
 (SUM(ps.reserved_page_count) - SUM(ps.used_page_count)) * 8 / 1024 AS Unused_MB,
 SUM(ps.used_page_count)                                            AS Used_Page_Count
FROM
 sys.dm_db_partition_stats ps
WHERE ps.object_id IN ( OBJECT_ID('dbo.DimCustomersCompressed'),
                        OBJECT_ID('dbo.DimCustomersOptimized'))
GROUP BY ps.object_id;

/* =============================================================
   Row compression
============================================================= */

-- Apply ROW compression to reduce storage by removing padding from fixed-length character data
-- and using more compact storage for numeric and date/time values
ALTER INDEX PK_DimCustomersCompressed
 ON dbo.DimCustomersCompressed
 REBUILD
 WITH (DATA_COMPRESSION = ROW);
GO


-- Check the space savings with row compression
WITH TableSpace
AS (SELECT
     ps.object_id,
     SUM(ps.used_page_count) AS Used_Page_Count
    FROM
     sys.dm_db_partition_stats ps
    WHERE ps.object_id IN ( OBJECT_ID('dbo.DimCustomersCompressed'),
                            OBJECT_ID('dbo.DimCustomersOptimized'))
    GROUP BY ps.object_id)
SELECT
 OBJECT_NAME(object_id)                                AS Table_Name,
 Used_Page_Count * 8 / 1024.0                          AS Used_MB,
 Used_Page_Count                                       AS Used_Pages,
 CAST((MAX(Used_Page_Count) OVER () - Used_Page_Count) * 100.0
      / MAX(Used_Page_Count) OVER () AS decimal(6, 2)) AS Percent_Saved
FROM
 TableSpace;

/* =============================================================
  Page compression
============================================================= */

-- Apply PAGE compression which includes ROW compression plus additional dictionary and prefix compression
-- This achieves higher compression ratios at the cost of slightly more CPU usage
ALTER INDEX PK_DimCustomersCompressed
 ON dbo.DimCustomersCompressed
 REBUILD
 WITH (DATA_COMPRESSION = PAGE);
GO


-- Check the space savings with page compression
WITH TableSpace
AS (SELECT
     ps.object_id,
     SUM(ps.used_page_count) AS Used_Page_Count
    FROM
     sys.dm_db_partition_stats ps
    WHERE ps.object_id IN ( OBJECT_ID('dbo.DimCustomersCompressed'),
                            OBJECT_ID('dbo.DimCustomersOptimized'))
    GROUP BY ps.object_id)
SELECT
 OBJECT_NAME(object_id)                                AS Table_Name,
 Used_Page_Count * 8 / 1024.0                          AS Used_MB,
 Used_Page_Count                                       AS Used_Pages,
 CAST((MAX(Used_Page_Count) OVER () - Used_Page_Count) * 100.0
      / MAX(Used_Page_Count) OVER () AS decimal(6, 2)) AS Percent_Saved
FROM
 TableSpace;

-- Display buffer pool usage to understand caching impact of compression
SELECT
 OBJECT_NAME(p.object_id) AS Table_Name,
 COUNT(*)                 AS Cached_Pages,
 COUNT(*) * 8 / 1024.0    AS Cached_MB
FROM
 sys.dm_os_buffer_descriptors bd
 JOIN sys.allocation_units    au
  ON bd.allocation_unit_id = au.allocation_unit_id
 JOIN sys.partitions          p
  ON au.container_id = p.hobt_id
WHERE bd.database_id = DB_ID()
      AND p.object_id IN ( OBJECT_ID('dbo.DimCustomersOptimized'),
                           OBJECT_ID('dbo.DimCustomersCompressed'))
GROUP BY p.object_id
ORDER BY Table_Name;

/* =============================================================
   Compare query performance
============================================================= */
SET STATISTICS IO, TIME ON;

SELECT
 TOP 1000
 *
FROM
 dbo.DimCustomersCompressed
WHERE StateName = 'Indiana'
ORDER BY EmailAddress DESC;

SELECT
 TOP 1000
 *
FROM
 dbo.DimCustomersOptimized
WHERE StateName = 'Indiana'
ORDER BY EmailAddress DESC;

SET STATISTICS IO, TIME OFF;

-- Microsoft article for row compression
-- https://learn.microsoft.com/en-us/sql/relational-databases/data-compression/row-compression-implementation

-- Microsoft article for page compression
-- https://learn.microsoft.com/en-us/sql/relational-databases/data-compression/page-compression-implementation

-- SQL Server Page Compression: Should You Worry About CPU Usage Increasing on Inserts, Updates, and Deletes?
-- https://kendralittle.com/2024/09/08/sql-server-page-compression-cpu-on-insert-update-delete/