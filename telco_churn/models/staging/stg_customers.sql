/*
  stg_customers.sql
  -----------------
  Staging layer: loads raw train.csv and applies three transformations only:
    1. Rename columns to snake_case
    2. Cast to correct types
    3. Normalize multi-value strings to clean binary flags (Yes/No → 1/0;
       "No phone service" / "No internet service" → 0)

  No feature engineering lives here — that belongs in int_churn_features.sql.

  Run command (from kaggle_competition/ directory):
    dbt run --select stg_customers --project-dir telco_churn --profiles-dir .
*/

{{ config(materialized='table') }}

with source as (

    /*
      DuckDB reads the CSV directly; path is relative to the working directory
      where `dbt run` is invoked (kaggle_competition/).
      header=true auto-detects column names from row 1.
      all_varchar=true prevents DuckDB from mistyping TotalCharges when it is blank.
    */
    select *
    from read_csv(
        '{{ var("raw_data_path") }}/train.csv',
        header      = true,
        all_varchar = true
    )

),

renamed_and_cast as (

    select
        -- ------------------------------------------------------------------ --
        -- Identifiers (kept for joining; drop before modeling)
        -- ------------------------------------------------------------------ --
        cast("id" as integer)                                as customer_id,

        -- ------------------------------------------------------------------ --
        -- Demographics
        -- ------------------------------------------------------------------ --
        "gender"                                             as gender,

        cast("SeniorCitizen" as integer)                     as is_senior_citizen,

        -- Yes/No → 1/0
        case when "Partner"    = 'Yes' then 1 else 0 end     as has_partner,
        case when "Dependents" = 'Yes' then 1 else 0 end     as has_dependents,

        -- ------------------------------------------------------------------ --
        -- Account info
        -- ------------------------------------------------------------------ --
        cast("tenure" as integer)                            as tenure_months,

        "Contract"                                           as contract_type,

        case when "PaperlessBilling" = 'Yes' then 1 else 0 end as has_paperless_billing,

        "PaymentMethod"                                      as payment_method,

        cast("MonthlyCharges" as decimal(10, 2))             as monthly_charges,

        -- TotalCharges is blank (not null) when tenure = 0; coerce blank → NULL
        case
            when trim("TotalCharges") = '' then null
            else cast("TotalCharges" as decimal(10, 2))
        end                                                  as total_charges,

        -- ------------------------------------------------------------------ --
        -- Phone services
        -- ------------------------------------------------------------------ --
        case when "PhoneService"  = 'Yes' then 1 else 0 end  as has_phone_service,

        -- "No phone service" treated the same as "No"
        case when "MultipleLines" = 'Yes' then 1 else 0 end  as has_multiple_lines,

        -- ------------------------------------------------------------------ --
        -- Internet service tier
        -- ------------------------------------------------------------------ --
        "InternetService"                                    as internet_service,

        -- ------------------------------------------------------------------ --
        -- Internet add-on services
        -- "No internet service" treated the same as "No" (customer opted out entirely)
        -- ------------------------------------------------------------------ --
        case when "OnlineSecurity"   = 'Yes' then 1 else 0 end as has_online_security,
        case when "OnlineBackup"     = 'Yes' then 1 else 0 end as has_online_backup,
        case when "DeviceProtection" = 'Yes' then 1 else 0 end as has_device_protection,
        case when "TechSupport"      = 'Yes' then 1 else 0 end as has_tech_support,
        case when "StreamingTV"      = 'Yes' then 1 else 0 end as has_streaming_tv,
        case when "StreamingMovies"  = 'Yes' then 1 else 0 end as has_streaming_movies,

        -- ------------------------------------------------------------------ --
        -- Target variable (train only; absent from test.csv)
        -- ------------------------------------------------------------------ --
        case when "Churn" = 'Yes' then 1 else 0 end           as churn

    from source

)

select * from renamed_and_cast
