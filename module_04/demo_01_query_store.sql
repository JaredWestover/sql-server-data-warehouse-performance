/* =============================================================
   Demo 01: Analyze warehouse workloads
   Module 04: Monitor and optimize warehouse workloads

   Download the demo files for this course from the following link:
   https://github.com/JaredWestover/sql-server-data-warehouse-performance
============================================================= */

USE DataWarehouseDemo;
GO

-- Check current Query Store configuration
SELECT
 actual_state_desc,
 current_storage_size_mb,
 max_storage_size_mb,
 query_capture_mode_desc,
 size_based_cleanup_mode_desc,
 stale_query_threshold_days,
 flush_interval_seconds,
 interval_length_minutes,
 max_plans_per_query,
 wait_stats_capture_mode_desc
FROM
 sys.database_query_store_options;
GO

-- Demo only: clears all Query Store data
ALTER DATABASE DataWarehouseDemo
 SET
  QUERY_STORE CLEAR;
GO

-- Run sample reporting queries
SELECT
 f.OrderDate,
 f.SalesKey,
 f.OrderNumber,
 f.OrderRiskCategory,
 f.CustomerKey,
 f.SalesAmount
FROM
 dbo.FactSalesCompressed f
WHERE f.OrderDate = '20270115'
ORDER BY f.SalesAmount DESC,
         f.SalesKey;
GO

SELECT
 f.OrderDate,
 SUM(f.SalesAmount)                                                           AS DailySales,
 SUM(SUM(f.SalesAmount)) OVER (ORDER BY f.OrderDate ROWS UNBOUNDED PRECEDING) AS RunningTotalSales
FROM
 dbo.FactSalesCompressed f
GROUP BY f.OrderDate
ORDER BY f.OrderDate;
GO

-- Run a resource-intensive median sales query
WITH Medians
AS (
   SELECT
    PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY SalesAmount) OVER (PARTITION BY ProductKey, StoreKey) AS Median_Product_Store,
    PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY SalesAmount) OVER (PARTITION BY ProductKey)           AS Median_Product,
    PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY SalesAmount) OVER (PARTITION BY StoreKey, OrderDate)  AS Median_Store_Day
   FROM
    dbo.FactSalesCompressed
   )
SELECT
 COUNT(*)                  AS Row_Count,
 MAX(Median_Product_Store) AS Max_Median_Product_Store,
 MAX(Median_Product)       AS Max_Median_Product,
 MAX(Median_Store_Day)     AS Max_Median_Store_Day
FROM
 Medians;
GO