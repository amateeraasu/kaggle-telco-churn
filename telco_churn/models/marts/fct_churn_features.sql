/*
  fct_churn_features.sql
  ----------------------
  Final feature mart — one row per customer, all features present and ML-ready.
  This is the single source of truth consumed by the ML notebook.

  Column selection rationale:
  - Identifiers (customer_id) kept for traceability but dropped before modeling
  - Raw features kept alongside engineered features so the notebook can compare
  - target column (churn) included last for convention
  - Columns that are pure intermediaries (raw string categoricals used only to
    derive binary flags) are also included for EDA completeness

  The notebook reads this table with:
    con = duckdb.connect("telco_churn.duckdb")
    df  = con.sql("SELECT * FROM marts.fct_churn_features").df()
*/

{{ config(materialized='table') }}

with features as (

    select * from {{ ref('int_churn_features') }}

),

final as (

    select
        -- ------------------------------------------------------------------ --
        -- Identifiers (drop before modeling)
        -- ------------------------------------------------------------------ --
        customer_id,

        -- ------------------------------------------------------------------ --
        -- Demographics (raw)
        -- ------------------------------------------------------------------ --
        gender,                   -- encode in notebook: Male=1, Female=0
        is_senior_citizen,
        has_partner,
        has_dependents,

        -- ------------------------------------------------------------------ --
        -- Account features (raw)
        -- ------------------------------------------------------------------ --
        tenure_months,
        contract_type,            -- one-hot or ordinal encode in notebook
        has_paperless_billing,
        payment_method,           -- one-hot encode in notebook
        monthly_charges,
        total_charges,

        -- ------------------------------------------------------------------ --
        -- Phone features (raw binary)
        -- ------------------------------------------------------------------ --
        has_phone_service,
        has_multiple_lines,

        -- ------------------------------------------------------------------ --
        -- Internet service (raw)
        -- ------------------------------------------------------------------ --
        internet_service,         -- one-hot encode in notebook

        -- ------------------------------------------------------------------ --
        -- Add-on services (raw binary)
        -- ------------------------------------------------------------------ --
        has_online_security,
        has_online_backup,
        has_device_protection,
        has_tech_support,
        has_streaming_tv,
        has_streaming_movies,

        -- ------------------------------------------------------------------ --
        -- Engineered features (SQL-only, no Python engineering required)
        -- ------------------------------------------------------------------ --
        tenure_group,             -- ordinal cohort bucket
        contract_risk_score,      -- ordinal: 3=M2M, 2=1yr, 1=2yr
        charges_ratio,            -- monthly_charges / tenure_months
        service_count,            -- sum of 6 internet add-on flags (0–6)
        has_any_streaming,        -- stickiness: TV or movies subscription
        has_any_security,         -- stickiness: security or tech support
        is_fiber_optic,           -- high-churn internet tier flag
        is_electronic_check,      -- manual payment = lower switching friction
        is_high_risk,             -- composite: M2M + fiber + tenure < 12 mo
        monthly_charges_bucket,   -- non-linear charge bands; $70-90 churns most
        services_per_dollar,      -- add-on density per $ spent (value perception)
        tenure_contract_segment,  -- crossed label e.g. 'M2M_0to12'

        -- ------------------------------------------------------------------ --
        -- Target (last by convention; absent from fct_churn_features_test)
        -- ------------------------------------------------------------------ --
        churn

    from features

)

select * from final
