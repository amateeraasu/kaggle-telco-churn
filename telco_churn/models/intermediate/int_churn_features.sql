/*
  int_churn_features.sql
  ----------------------
  Intermediate layer: ALL feature engineering lives here, in SQL.
  The ML notebook reads from fct_churn_features and does zero feature engineering —
  only encoding and modeling. This is the Analytics Engineer differentiator.

  Design principles:
  - Every derived column has a comment explaining the business logic
  - SQL is the source of truth for feature definitions; Python just consumes them
  - Features are named to be self-documenting in SHAP plots

  Features added beyond the raw staging columns:
  ┌──────────────────────────┬────────────────────────────────────────────────────────┐
  │ Feature                  │ Business logic                                         │
  ├──────────────────────────┼────────────────────────────────────────────────────────┤
  │ tenure_group             │ Cohort buckets: churn risk is non-linear with tenure   │
  │ contract_risk_score      │ Ordinal commitment signal: M2M=3, 1yr=2, 2yr=1        │
  │ charges_ratio            │ Avg monthly spend intensity relative to tenure         │
  │ service_count            │ Internet add-ons purchased (switching cost proxy)      │
  │ has_any_streaming        │ Entertainment stickiness flag                          │
  │ has_any_security         │ Security add-on stickiness flag                        │
  │ is_fiber_optic           │ Fiber customers churn at higher rates                  │
  │ is_electronic_check      │ Least committed payment type (manual, not auto)        │
  │ is_high_risk             │ Composite worst-case flag for intervention targeting   │
  └──────────────────────────┴────────────────────────────────────────────────────────┘
*/

{{ config(materialized='table') }}

with customers as (

    select * from {{ ref('stg_customers') }}

),

features as (

    select
        -- ------------------------------------------------------------------ --
        -- Pass-through columns from staging
        -- ------------------------------------------------------------------ --
        customer_id,
        gender,
        is_senior_citizen,
        has_partner,
        has_dependents,
        tenure_months,
        contract_type,
        has_paperless_billing,
        payment_method,
        monthly_charges,
        total_charges,
        has_phone_service,
        has_multiple_lines,
        internet_service,
        has_online_security,
        has_online_backup,
        has_device_protection,
        has_tech_support,
        has_streaming_tv,
        has_streaming_movies,
        churn,

        -- ------------------------------------------------------------------ --
        -- FEATURE: tenure_group
        -- Bucket tenure into cohorts because churn risk is highest in the first
        -- year and drops off non-linearly — a linear tenure term misses this.
        -- Labels match the intervals: [0,12), [12,24), [24,48), [48,72].
        -- ------------------------------------------------------------------ --
        case
            when tenure_months between 0  and 11 then '0-12 mo'
            when tenure_months between 12 and 23 then '12-24 mo'
            when tenure_months between 24 and 47 then '24-48 mo'
            else                                      '48+ mo'
        end as tenure_group,

        -- ------------------------------------------------------------------ --
        -- FEATURE: contract_risk_score
        -- Ordinal encoding of contract commitment level.
        -- Month-to-month customers have no lock-in and churn at ~3x the rate
        -- of two-year contract customers.  Score: 3=highest risk, 1=lowest.
        -- ------------------------------------------------------------------ --
        case contract_type
            when 'Month-to-month' then 3
            when 'One year'       then 2
            when 'Two year'       then 1
        end as contract_risk_score,

        -- ------------------------------------------------------------------ --
        -- FEATURE: charges_ratio
        -- Monthly charges divided by tenure (average monthly spend intensity).
        -- A customer who pays $90/mo after 1 month is riskier than one paying
        -- $90/mo after 36 months — the latter has demonstrated loyalty.
        -- NULL when tenure_months = 0 to avoid division by zero.
        -- ------------------------------------------------------------------ --
        case
            when tenure_months > 0
                then round(monthly_charges / tenure_months, 4)
            else null
        end as charges_ratio,

        -- ------------------------------------------------------------------ --
        -- FEATURE: service_count
        -- Count of internet add-on services subscribed (0–6).
        -- Each additional service raises switching costs: a customer with
        -- online backup, security, and tech support has 3 reasons to stay.
        -- ------------------------------------------------------------------ --
        (
            has_online_security  +
            has_online_backup    +
            has_device_protection +
            has_tech_support     +
            has_streaming_tv     +
            has_streaming_movies
        ) as service_count,

        -- ------------------------------------------------------------------ --
        -- FEATURE: has_any_streaming
        -- Flag for entertainment subscription (TV or movies).
        -- Streaming services create habitual daily engagement, reducing churn.
        -- ------------------------------------------------------------------ --
        case
            when has_streaming_tv = 1 or has_streaming_movies = 1 then 1
            else 0
        end as has_any_streaming,

        -- ------------------------------------------------------------------ --
        -- FEATURE: has_any_security
        -- Flag for security/support subscription (online security or tech support).
        -- Security-focused customers tend to be more risk-averse about switching.
        -- ------------------------------------------------------------------ --
        case
            when has_online_security = 1 or has_tech_support = 1 then 1
            else 0
        end as has_any_security,

        -- ------------------------------------------------------------------ --
        -- FEATURE: is_fiber_optic
        -- Fiber optic internet customers churn more than DSL or no-internet.
        -- Likely because fiber markets are more competitive and the service is
        -- priced higher, attracting price-sensitive customers.
        -- ------------------------------------------------------------------ --
        case when internet_service = 'Fiber optic' then 1 else 0 end
            as is_fiber_optic,

        -- ------------------------------------------------------------------ --
        -- FEATURE: is_electronic_check
        -- Electronic check payers show systematically higher churn than
        -- automatic payment customers (bank transfer or credit card auto).
        -- Manual payment = less friction to cancel.
        -- ------------------------------------------------------------------ --
        case when payment_method = 'Electronic check' then 1 else 0 end
            as is_electronic_check,

        -- ------------------------------------------------------------------ --
        -- FEATURE: is_high_risk
        -- Composite flag targeting the worst-case churn profile:
        --   • Month-to-month contract (no lock-in)
        --   • Fiber optic (high cost, competitive market)
        --   • Tenure < 12 months (honeymoon period not yet converted to loyalty)
        -- Customers matching all three conditions are primary intervention targets.
        -- ------------------------------------------------------------------ --
        case
            when contract_type   = 'Month-to-month'
             and internet_service = 'Fiber optic'
             and tenure_months    < 12
            then 1
            else 0
        end as is_high_risk

    from customers

)

select * from features
