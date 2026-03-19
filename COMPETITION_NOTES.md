# Competition Notes — Kaggle Playground Series S6E3

## Overview
- **Name**: Predict Customer Churn
- **URL**: https://www.kaggle.com/competitions/playground-series-s6e3
- **Type**: Binary Classification
- **Citation**: Yao Yan, Walter Reade, Elizabeth Park. Predict Customer Churn. Kaggle, 2026.

## Problem Description
Predict whether a telecommunications customer will churn (cancel their service) based on
account demographics, service subscriptions, and billing information. The synthetic dataset
was generated from the Telco Customer Churn dataset using a deep learning model, preserving
feature distributions while adding synthetic variation.

## Evaluation Metric
**Area Under the ROC Curve (AUC-ROC)**
Submissions are evaluated on the AUC between predicted probability and the observed target `Churn`.
Higher is better; 0.5 = random, 1.0 = perfect.

**Implication for modeling:**
- Optimize for ROC-AUC, not accuracy
- Report probability scores (not hard labels) in submission
- Tune decision threshold using Precision-Recall curve for business-facing metrics

## Target Variable
- **Column name**: `Churn`
- **Training encoding**: `"Yes"` / `"No"` (string)
- **Submission encoding**: Float probability in [0, 1] (see sample_submission.csv)
- **Churn rate**: 22.5% (133,817 / 594,194 rows) — moderate imbalance, use class_weight='balanced'

## Dataset Shape
| Split       | Rows    | Columns |
|-------------|---------|---------|
| train.csv   | 594,194 | 21      |
| test.csv    | ~       | 20      |
| sample_sub  | ~       | 2       |

## Exact Column Names and Descriptions

| Column           | Type       | Description                                              | Notes                          |
|------------------|------------|----------------------------------------------------------|--------------------------------|
| id               | integer    | Row identifier                                           | Drop before modeling           |
| gender           | string     | Customer gender: Male / Female                           | Encode binary                  |
| SeniorCitizen    | integer    | Whether customer is a senior citizen: 0 / 1              | Already binary                 |
| Partner          | string     | Whether customer has a partner: Yes / No                 | Encode binary                  |
| Dependents       | string     | Whether customer has dependents: Yes / No                | Encode binary                  |
| tenure           | integer    | Months customer has been with the company (0–72)         | Key churn signal               |
| PhoneService     | string     | Whether customer has phone service: Yes / No             | Encode binary                  |
| MultipleLines    | string     | Multiple phone lines: Yes / No / No phone service        | Treat 'No phone service' as No |
| InternetService  | string     | Internet type: DSL / Fiber optic / No                    | One-hot encode                 |
| OnlineSecurity   | string     | Online security add-on: Yes / No / No internet service   | Collapse to binary             |
| OnlineBackup     | string     | Online backup add-on: Yes / No / No internet service     | Collapse to binary             |
| DeviceProtection | string     | Device protection add-on: Yes / No / No internet service | Collapse to binary             |
| TechSupport      | string     | Tech support add-on: Yes / No / No internet service      | Collapse to binary             |
| StreamingTV      | string     | Streaming TV add-on: Yes / No / No internet service      | Collapse to binary             |
| StreamingMovies  | string     | Streaming movies add-on: Yes / No / No internet service  | Collapse to binary             |
| Contract         | string     | Contract type: Month-to-month / One year / Two year      | Key retention signal           |
| PaperlessBilling | string     | Whether billing is paperless: Yes / No                   | Encode binary                  |
| PaymentMethod    | string     | Payment method (4 values, see below)                     | One-hot encode                 |
| MonthlyCharges   | float      | Monthly amount billed to customer                        |                                |
| TotalCharges     | float      | Total amount billed over tenure                          | Blank when tenure=0 → NULL     |
| Churn            | string     | **TARGET**: Yes (churned) / No (retained)                | Encode to 1/0                  |

### PaymentMethod values
- Electronic check
- Mailed check
- Bank transfer (automatic)
- Credit card (automatic)

## Data Quality Notes
- `TotalCharges` can be blank when `tenure = 0` → cast to NULL in staging
- `MultipleLines`, `OnlineSecurity`, `OnlineBackup`, `DeviceProtection`, `TechSupport`,
  `StreamingTV`, `StreamingMovies` use three-valued strings — collapse "No X service" → 0
- No other documented nulls in the original dataset

## Key Churn Signals (from domain knowledge + EDA)
1. **Contract type**: Month-to-month customers churn at ~3x the rate of two-year contracts
2. **Tenure**: Churn is highest in the first 12 months; drops sharply after 24 months
3. **Internet service**: Fiber optic customers churn more than DSL (higher cost, more competition)
4. **Payment method**: Electronic check correlates with higher churn (least committed payment type)
5. **Add-on services**: Each additional service reduces churn probability (switching cost)
6. **Senior citizens**: Higher churn rate than non-seniors
7. **Total charges**: Low total charges + high monthly charges = short-tenure high-cost customers

## Feature Engineering Plan (implemented in int_churn_features.sql)
| Feature                | Logic                                         | Rationale                              |
|------------------------|-----------------------------------------------|----------------------------------------|
| tenure_group           | Bucket 0-12, 12-24, 24-48, 48+ months        | Non-linear tenure effect on churn      |
| contract_risk_score    | Month-to-month=3, One year=2, Two year=1      | Ordinal commitment signal              |
| charges_ratio          | monthly_charges / nullif(tenure_months, 0)    | Per-month cost intensity               |
| service_count          | Sum of 6 internet add-on binary flags         | Switching cost proxy                   |
| is_fiber_optic         | internet_service = 'Fiber optic'              | High-churn service tier                |
| is_electronic_check    | payment_method = 'Electronic check'           | Least committed payment type           |
| is_high_risk           | Month-to-month + Fiber optic + tenure < 12   | Composite worst-case flag              |
| has_any_streaming      | has_streaming_tv OR has_streaming_movies      | Entertainment stickiness               |
| has_any_security       | has_online_security OR has_tech_support       | Security add-on stickiness             |

## Architecture Decision Log
- **dbt project name**: `telco_churn` (confirmed: dataset is Telco, not bank)
- **Warehouse**: DuckDB (local, no external connection required)
- **ML features**: Engineered in SQL (dbt intermediate layer), NOT in Python notebook
- **Notebook reads from**: `fct_churn_features` mart table via DuckDB connection
- **Submission format**: `id`, `Churn` (float probability 0–1)
