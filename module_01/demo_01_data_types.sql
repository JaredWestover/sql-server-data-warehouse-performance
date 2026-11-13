/* =============================================================
   Demo 01: Reduce storage using appropriate data types
   Module 01: Optimize tables for warehouse performance

   Download the demo files for this course from the following link:
   https://github.com/JaredWestover/sql-server-data-warehouse-performance
============================================================= */

-- Check the SQL Server version and edition
SELECT
 SERVERPROPERTY('ProductVersion')     AS ProductVersion,
 SERVERPROPERTY('ProductLevel')       AS ProductLevel,
 SERVERPROPERTY('Edition')            AS Edition,
 SERVERPROPERTY('ProductUpdateLevel') AS ProductUpdateLevel,
 SERVERPROPERTY('ProductBuild')       AS ProductBuild;

-- Drop and recreate the DataWarehouseDemo database
USE [master];

IF DB_ID('DataWarehouseDemo') IS NOT NULL
BEGIN
 ALTER DATABASE DataWarehouseDemo
  SET
   SINGLE_USER
  WITH ROLLBACK IMMEDIATE;

 DROP DATABASE DataWarehouseDemo;
END;

CREATE DATABASE DataWarehouseDemo;
GO


-- Preallocate 10 GB for the data file
ALTER DATABASE DataWarehouseDemo
 MODIFY FILE
  (NAME = N'DataWarehouseDemo',
   SIZE = 10GB,
   FILEGROWTH = 1GB);
GO


-- Preallocate 1 GB for the log file
ALTER DATABASE DataWarehouseDemo
 MODIFY FILE
  (NAME = N'DataWarehouseDemo_log',
   SIZE = 1GB,
   FILEGROWTH = 1GB);
GO


-- Set the recovery model to SIMPLE
ALTER DATABASE DataWarehouseDemo
 SET
  RECOVERY SIMPLE;
GO


USE DataWarehouseDemo;
GO


-- Create the original table
CREATE TABLE dbo.DimCustomers
(
 CustomerKey  bigint     NOT NULL,
 FirstName    nchar(200) NULL,
 LastName     nchar(200) NULL,
 StateName    nchar(50)  NULL,
 PhoneNumber  nchar(200) NULL,
 EmailAddress nchar(200) NULL,
 Notes        char(200)  NULL,
 IsActive     bit        NOT NULL
  DEFAULT (1),
 CONSTRAINT PK_DimCustomers
  PRIMARY KEY CLUSTERED (CustomerKey)
  WITH(FILLFACTOR = 100)
);

-- Insert 2 million rows into the table
INSERT INTO dbo.DimCustomers WITH (TABLOCK)
(
 CustomerKey,
 FirstName,
 LastName,
 StateName,
 PhoneNumber,
 EmailAddress,
 Notes
)
SELECT
 value,
 N'First' + CAST((value % 1000) AS nvarchar(10)),
 N'Last' + CAST((value % 5000) AS nvarchar(10)),
 CASE value % 5
  WHEN 0 THEN N'Indiana'
  WHEN 1 THEN N'Ohio'
  WHEN 2 THEN N'Illinois'
  WHEN 3 THEN N'Michigan'
  WHEN 4 THEN N'Kentucky'
  ELSE NULL END,
 N'555-' + RIGHT('0000' + CAST((value % 10000) AS nvarchar(4)), 4),
 N'customer' + CAST(value AS nvarchar(20)) + N'@example.com',
 N'Demo customer record'
FROM
 GENERATE_SERIES(1, 2000000);
GO


-- Allow inactive log space to be reused
CHECKPOINT;
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
WHERE ps.object_id = OBJECT_ID('dbo.DimCustomers')
GROUP BY ps.object_id;
GO


-- Create the optimized table
CREATE TABLE dbo.DimCustomersOptimized
(
 CustomerKey  int         NOT NULL,
 FirstName    varchar(20) NULL,
 LastName     varchar(20) NULL,
 StateName    varchar(20) NULL,
 PhoneNumber  varchar(12) NULL,
 EmailAddress varchar(50) NULL,
 Notes        varchar(50) NULL,
 IsActive     bit         NOT NULL
  DEFAULT (1),
 CONSTRAINT PK_DimCustomersOptimized
  PRIMARY KEY CLUSTERED (CustomerKey)
  WITH(FILLFACTOR = 100)
);

-- Insert the same 2 million rows into the optimized table
INSERT INTO dbo.DimCustomersOptimized WITH (TABLOCK)
(
 CustomerKey,
 FirstName,
 LastName,
 StateName,
 PhoneNumber,
 EmailAddress,
 Notes
)
SELECT
 value,
 'First' + CAST((value % 1000) AS varchar(10)),
 'Last' + CAST((value % 5000) AS varchar(10)),
 CASE value % 5
  WHEN 0 THEN 'Indiana'
  WHEN 1 THEN 'Ohio'
  WHEN 2 THEN 'Illinois'
  WHEN 3 THEN 'Michigan'
  WHEN 4 THEN 'Kentucky'
  ELSE NULL END,
 '555-' + RIGHT('0000' + CAST((value % 10000) AS varchar(4)), 4),
 'customer' + CAST(value AS varchar(20)) + '@example.com',
 'Demo customer record'
FROM
 GENERATE_SERIES(1, 2000000);
GO


-- Allow inactive log space to be reused
CHECKPOINT;
GO


-- Compare storage between the tables
SELECT
 OBJECT_NAME(ps.object_id)                                          AS Table_Name,
 SUM(ps.reserved_page_count) * 8 / 1024.0                           AS Reserved_MB,
 SUM(ps.used_page_count) * 8 / 1024.0                               AS Used_MB,
 (SUM(ps.reserved_page_count) - SUM(ps.used_page_count)) * 8 / 1024 AS Unused_MB,
 SUM(ps.used_page_count)                                            AS Used_Page_Count
FROM
 sys.dm_db_partition_stats ps
WHERE ps.object_id IN ( OBJECT_ID('dbo.DimCustomers'),
                        OBJECT_ID('dbo.DimCustomersOptimized'))
GROUP BY ps.object_id;
GO


-- Compare query performance
SET STATISTICS IO, TIME ON;

SELECT
 TOP 1000
 *
FROM
 dbo.DimCustomers
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
GO

/*
Further Reading
SQL Server Table Design Guide – Data Types, Primary Keys and more
https://www.mssqltips.com/sqlservertip/7829/sql-server-table-design-guide-data-types-deletes-and-primary-keys/
*/