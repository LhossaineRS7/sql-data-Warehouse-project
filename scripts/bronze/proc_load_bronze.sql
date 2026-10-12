/*
===============================================================================
Stored Procedure: Load Bronze Layer (Source -> Bronze)
===============================================================================
Script Purpose:
    This stored procedure loads data into the 'bronze' schema from external CSV files.
    It performs the following actions:
    - Truncates the existing bronze tables before ingestion (Full Truncate & Load).
    - Uses the PostgreSQL 'COPY' command to bulk load data from CSV files.
    - Measures, computes, and logs the execution duration for each table and source batch.

Parameters:
    None.
    This stored procedure does not accept any parameters or return any values.

Usage Example:
    CALL bronze.load_bronze();
===============================================================================
*/
call bronze.load_bronze();
CREATE OR REPLACE PROCEDURE bronze.load_bronze()
LANGUAGE plpgsql
AS $$
DECLARE 
    proc_start_time  TIMESTAMP;
    batch_start_time TIMESTAMP;
    step_start_time  TIMESTAMP;
    step_end_time    TIMESTAMP;
BEGIN 
    proc_start_time := clock_timestamp();

    RAISE NOTICE '==========================================';
    RAISE NOTICE 'Starting Bronze Layer Load';
    RAISE NOTICE '==========================================';

    -- -----------------------------------------------------------------
    -- 1. CRM Tables
    -- -----------------------------------------------------------------
    batch_start_time := clock_timestamp();
    RAISE NOTICE '>> Loading CRM Tables...';

    -- CRM: Customer Info
    step_start_time := clock_timestamp();
    TRUNCATE TABLE bronze.crm_cust_info;
    COPY bronze.crm_cust_info
    FROM '/tmp/datasets/source_crm/cust_info.csv'
    WITH (FORMAT csv, HEADER true, DELIMITER ',');
    step_end_time := clock_timestamp();
    RAISE NOTICE '   - bronze.crm_cust_info loaded in %s', 
        ROUND(EXTRACT(EPOCH FROM (step_end_time - step_start_time))::NUMERIC, 2);

    -- CRM: Product Info
    step_start_time := clock_timestamp();
    TRUNCATE TABLE bronze.crm_prd_info;
    COPY bronze.crm_prd_info
    FROM '/tmp/datasets/source_crm/prd_info.csv'
    WITH (FORMAT csv, HEADER true, DELIMITER ',');
    step_end_time := clock_timestamp();
    RAISE NOTICE '   - bronze.crm_prd_info loaded in %s', 
        ROUND(EXTRACT(EPOCH FROM (step_end_time - step_start_time))::NUMERIC, 2);

    -- CRM: Sales Details
    step_start_time := clock_timestamp();
    TRUNCATE TABLE bronze.crm_sales_details;
    COPY bronze.crm_sales_details
    FROM '/tmp/datasets/source_crm/sales_details.csv'
    WITH (FORMAT csv, HEADER true, DELIMITER ',');
    step_end_time := clock_timestamp();
    RAISE NOTICE '   - bronze.crm_sales_details loaded in %s', 
        ROUND(EXTRACT(EPOCH FROM (step_end_time - step_start_time))::NUMERIC, 2);

    RAISE NOTICE '>> CRM Tables loaded successfully in %s', 
        ROUND(EXTRACT(EPOCH FROM (clock_timestamp() - batch_start_time))::NUMERIC, 2);

    -- -----------------------------------------------------------------
    -- 2. ERP Tables
    -- -----------------------------------------------------------------
    batch_start_time := clock_timestamp();
    RAISE NOTICE '>> Loading ERP Tables...';

    -- ERP: Customer AZ12
    step_start_time := clock_timestamp();
    TRUNCATE TABLE bronze.erp_cust_az12;
    COPY bronze.erp_cust_az12
    FROM '/tmp/datasets/source_erp/CUST_AZ12.csv'
    WITH (FORMAT csv, HEADER true, DELIMITER ',');
    step_end_time := clock_timestamp();
    RAISE NOTICE '   - bronze.erp_cust_az12 loaded in %s', 
        ROUND(EXTRACT(EPOCH FROM (step_end_time - step_start_time))::NUMERIC, 2);

    -- ERP: Location A101
    step_start_time := clock_timestamp();
    TRUNCATE TABLE bronze.erp_loc_a101;
    COPY bronze.erp_loc_a101
    FROM '/tmp/datasets/source_erp/LOC_A101.csv'
    WITH (FORMAT csv, HEADER true, DELIMITER ',');
    step_end_time := clock_timestamp();
    RAISE NOTICE '   - bronze.erp_loc_a101 loaded in %s', 
        ROUND(EXTRACT(EPOCH FROM (step_end_time - step_start_time))::NUMERIC, 2);

    -- ERP: PX Category
    step_start_time := clock_timestamp();
    TRUNCATE TABLE bronze.erp_px_cat_g1v2;
    COPY bronze.erp_px_cat_g1v2
    FROM '/tmp/datasets/source_erp/PX_CAT_G1V2.csv'
    WITH (FORMAT csv, HEADER true, DELIMITER ',');
    step_end_time := clock_timestamp();
    RAISE NOTICE '   - bronze.erp_px_cat_g1v2 loaded in %s', 
        ROUND(EXTRACT(EPOCH FROM (step_end_time - step_start_time))::NUMERIC, 2);

    RAISE NOTICE '>> ERP Tables loaded successfully in %s', 
        ROUND(EXTRACT(EPOCH FROM (clock_timestamp() - batch_start_time))::NUMERIC, 2);

    -- -----------------------------------------------------------------
    -- Completion Summary
    -- -----------------------------------------------------------------
    RAISE NOTICE '==========================================';
    RAISE NOTICE 'Bronze Load Completed in %s!', 
        ROUND(EXTRACT(EPOCH FROM (clock_timestamp() - proc_start_time))::NUMERIC, 2);
    RAISE NOTICE '==========================================';

EXCEPTION 
    WHEN OTHERS THEN 	
        RAISE WARNING '================================================';
        RAISE WARNING 'ERROR OCCURRED WHILE LOADING BRONZE LAYER:';
        RAISE WARNING 'Error Message: %', SQLERRM;
        RAISE WARNING 'Error State:   %', SQLSTATE;
        RAISE WARNING '================================================';
        -- Re-throw exception so the transaction rolls back and caller detects failure
        RAISE;
END;
$$;
