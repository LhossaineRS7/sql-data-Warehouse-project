-- =====================================================================
-- Procedure: silver.load_silver()
-- Purpose  : Clean data from the bronze layer and load it into silver
-- Usage    : CALL silver.load_silver();
-- Tables   : crm_prd_info, crm_sales_details,
--            erp_cust_az12, erp_loc_a101, erp_px_cat_g1v2
-- =====================================================================

CREATE OR REPLACE PROCEDURE silver.load_silver()
LANGUAGE plpgsql
AS $$
DECLARE
    batch_start  TIMESTAMP;
    batch_end    TIMESTAMP;
    start_time   TIMESTAMP;
    end_time     TIMESTAMP;
    row_count    BIGINT;
BEGIN
    batch_start := clock_timestamp();
    RAISE NOTICE '================================================';
    RAISE NOTICE 'Loading Silver Layer';
    RAISE NOTICE '================================================';

    ------------------------------------------------------------------
    -- 1) silver.crm_prd_info
    ------------------------------------------------------------------
    start_time := clock_timestamp();
    RAISE NOTICE '>> Truncating table: silver.crm_prd_info';
    TRUNCATE TABLE silver.crm_prd_info;

    RAISE NOTICE '>> Inserting data into: silver.crm_prd_info';
    INSERT INTO silver.crm_prd_info (
        prd_id,
        cat_id,
        prd_key,
        prd_nm,
        prd_cost,
        prd_line,
        prd_start_dt,
        prd_end_dt
    )
    SELECT
        prd_id,
        REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_') AS cat_id,        -- extract category id
        SUBSTRING(prd_key, 7, LENGTH(prd_key))      AS prd_key,       -- extract product key
        prd_nm,
        COALESCE(prd_cost, 0)                       AS prd_cost,
        CASE UPPER(TRIM(prd_line))                                    -- map codes to descriptive values
            WHEN 'M' THEN 'Mountain'
            WHEN 'R' THEN 'Road'
            WHEN 'S' THEN 'Other Sales'
            WHEN 'T' THEN 'Touring'
            ELSE 'n/a'
        END                                         AS prd_line,
        CAST(prd_start_dt AS DATE)                  AS prd_start_dt,
        -- end date = one day before the next start date (data enrichment)
        CAST(
            LEAD(prd_start_dt) OVER (
                PARTITION BY prd_key
                ORDER BY prd_start_dt
            ) - INTERVAL '1 day' AS DATE
        )                                           AS prd_end_dt
    FROM bronze.crm_prd_info;

    GET DIAGNOSTICS row_count = ROW_COUNT;
    end_time := clock_timestamp();
    RAISE NOTICE '>> % rows loaded in % seconds',
        row_count, ROUND(EXTRACT(EPOCH FROM (end_time - start_time))::NUMERIC, 2);

    ------------------------------------------------------------------
    -- 2) silver.crm_sales_details
    ------------------------------------------------------------------
    start_time := clock_timestamp();
    RAISE NOTICE '>> Truncating table: silver.crm_sales_details';
    TRUNCATE TABLE silver.crm_sales_details;

    RAISE NOTICE '>> Inserting data into: silver.crm_sales_details';
    INSERT INTO silver.crm_sales_details (
        sls_ord_num,
        sls_prd_key,
        sls_cust_id,
        sls_order_dt,
        sls_ship_dt,
        sls_due_dt,
        sls_sales,
        sls_quantity,
        sls_price
    )
    SELECT
        sls_ord_num,
        sls_prd_key,
        sls_cust_id,
        CASE WHEN sls_order_dt = 0 OR LENGTH(CAST(sls_order_dt AS VARCHAR)) != 8 THEN NULL
             ELSE CAST(CAST(sls_order_dt AS VARCHAR) AS DATE)
        END AS sls_order_dt,
        CASE WHEN sls_ship_dt = 0 OR LENGTH(CAST(sls_ship_dt AS VARCHAR)) != 8 THEN NULL
             ELSE CAST(CAST(sls_ship_dt AS VARCHAR) AS DATE)
        END AS sls_ship_dt,
        -- NOTE: your original code had "!= 0" here, which nulls every due date; fixed to "!= 8"
        CASE WHEN sls_due_dt = 0 OR LENGTH(CAST(sls_due_dt AS VARCHAR)) != 8 THEN NULL
             ELSE CAST(CAST(sls_due_dt AS VARCHAR) AS DATE)
        END AS sls_due_dt,
        -- recompute sales if missing, invalid or inconsistent with quantity * price
        CASE WHEN sls_sales IS NULL OR sls_sales <= 0
                  OR sls_sales != sls_quantity * ABS(sls_price)
             THEN sls_quantity * ABS(sls_price)
             ELSE sls_sales
        END AS sls_sales,
        sls_quantity,
        -- derive price if missing or invalid
        CASE WHEN sls_price IS NULL OR sls_price <= 0
             THEN sls_sales / NULLIF(sls_quantity, 0)
             ELSE sls_price
        END AS sls_price
    FROM bronze.crm_sales_details;

    GET DIAGNOSTICS row_count = ROW_COUNT;
    end_time := clock_timestamp();
    RAISE NOTICE '>> % rows loaded in % seconds',
        row_count, ROUND(EXTRACT(EPOCH FROM (end_time - start_time))::NUMERIC, 2);

    ------------------------------------------------------------------
    -- 3) silver.erp_cust_az12
    ------------------------------------------------------------------
    start_time := clock_timestamp();
    RAISE NOTICE '>> Truncating table: silver.erp_cust_az12';
    TRUNCATE TABLE silver.erp_cust_az12;

    RAISE NOTICE '>> Inserting data into: silver.erp_cust_az12';
    INSERT INTO silver.erp_cust_az12 (cid, bdate, gen)
    SELECT
        CASE WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid, 4, LENGTH(cid))
             ELSE cid
        END AS cid,
        CASE WHEN bdate > CURRENT_TIMESTAMP THEN NULL      -- future birthdates -> NULL
             ELSE bdate
        END AS bdate,
        CASE WHEN UPPER(TRIM(gen)) IN ('F', 'FEMALE') THEN 'Female'
             WHEN UPPER(TRIM(gen)) IN ('M', 'MALE')   THEN 'Male'
             ELSE 'n/a'
        END AS gen
    FROM bronze.erp_cust_az12;

    GET DIAGNOSTICS row_count = ROW_COUNT;
    end_time := clock_timestamp();
    RAISE NOTICE '>> % rows loaded in % seconds',
        row_count, ROUND(EXTRACT(EPOCH FROM (end_time - start_time))::NUMERIC, 2);

    ------------------------------------------------------------------
    -- 4) silver.erp_loc_a101
    ------------------------------------------------------------------
    start_time := clock_timestamp();
    RAISE NOTICE '>> Truncating table: silver.erp_loc_a101';
    TRUNCATE TABLE silver.erp_loc_a101;

    RAISE NOTICE '>> Inserting data into: silver.erp_loc_a101';
    INSERT INTO silver.erp_loc_a101 (cid, cntry)
    SELECT
        REPLACE(cid, '-', '') AS cid,
        CASE WHEN TRIM(cntry) = 'DE'              THEN 'Germany'
             WHEN TRIM(cntry) IN ('US', 'USA')    THEN 'United States'
             WHEN TRIM(cntry) = '' OR cntry IS NULL THEN 'n/a'
             ELSE TRIM(cntry)
        END AS cntry
    FROM bronze.erp_loc_a101;

    GET DIAGNOSTICS row_count = ROW_COUNT;
    end_time := clock_timestamp();
    RAISE NOTICE '>> % rows loaded in % seconds',
        row_count, ROUND(EXTRACT(EPOCH FROM (end_time - start_time))::NUMERIC, 2);

    ------------------------------------------------------------------
    -- 5) silver.erp_px_cat_g1v2
    ------------------------------------------------------------------
    start_time := clock_timestamp();
    RAISE NOTICE '>> Truncating table: silver.erp_px_cat_g1v2';
    TRUNCATE TABLE silver.erp_px_cat_g1v2;

    RAISE NOTICE '>> Inserting data into: silver.erp_px_cat_g1v2';
    INSERT INTO silver.erp_px_cat_g1v2 (id, cat, subcat, maintenance)
    SELECT id, cat, subcat, maintenance
    FROM bronze.erp_px_cat_g1v2;

    GET DIAGNOSTICS row_count = ROW_COUNT;
    end_time := clock_timestamp();
    RAISE NOTICE '>> % rows loaded in % seconds',
        row_count, ROUND(EXTRACT(EPOCH FROM (end_time - start_time))::NUMERIC, 2);

    ------------------------------------------------------------------
    batch_end := clock_timestamp();
    RAISE NOTICE '================================================';
    RAISE NOTICE 'Silver layer loaded. Total time: % seconds',
        ROUND(EXTRACT(EPOCH FROM (batch_end - batch_start))::NUMERIC, 2);
    RAISE NOTICE '================================================';

EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '================================================';
        RAISE NOTICE 'ERROR while loading silver layer';
        RAISE NOTICE 'Message  : %', SQLERRM;
        RAISE NOTICE 'SQLSTATE : %', SQLSTATE;
        RAISE NOTICE '================================================';
        RAISE;   -- re-raise so the whole call rolls back
END;
$$;

-- Run it:
-- CALL silver.load_silver();


-- =====================================================================
-- QUALITY CHECKS (run these manually after the load, not in the procedure)
-- =====================================================================

-- crm_prd_info: duplicates or NULL ids
-- SELECT prd_id, COUNT(*) FROM silver.crm_prd_info GROUP BY prd_id HAVING COUNT(*) > 1 OR prd_id IS NULL;
-- SELECT DISTINCT prd_line FROM silver.crm_prd_info;
-- SELECT * FROM silver.crm_prd_info WHERE prd_end_dt < prd_start_dt;

-- crm_sales_details: invalid date order
-- SELECT * FROM silver.crm_sales_details WHERE sls_order_dt > sls_ship_dt OR sls_order_dt > sls_due_dt;
-- crm_sales_details: sales = quantity * price, no NULL / zero / negative
-- SELECT DISTINCT sls_sales, sls_quantity, sls_price
-- FROM silver.crm_sales_details
-- WHERE sls_sales != sls_quantity * sls_price
--    OR sls_sales IS NULL OR sls_quantity IS NULL OR sls_price IS NULL
--    OR sls_sales <= 0 OR sls_quantity <= 0 OR sls_price <= 0
-- ORDER BY sls_sales, sls_quantity, sls_price;

-- erp_cust_az12
-- SELECT DISTINCT bdate FROM silver.erp_cust_az12 WHERE bdate < '1924-01-01' OR bdate > CURRENT_TIMESTAMP;
-- SELECT DISTINCT gen FROM silver.erp_cust_az12;

-- erp_loc_a101
-- SELECT DISTINCT cntry FROM silver.erp_loc_a101;
