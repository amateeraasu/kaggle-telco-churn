# Telco Customer Churn — Portfolio Project

**Kaggle Playground Series S6E3** | Binary Classification | Evaluated on ROC-AUC

This project demonstrates an Analytics Engineering approach to ML: feature engineering
in SQL (dbt), ML modeling in Python that reads exclusively from the dbt mart.

---

## Architecture

```
kaggle_competition/
├── COMPETITION_NOTES.md          ← Problem framing, schema, design decisions
├── profiles.yml                  ← dbt DuckDB connection config
├── requirements.txt
│
├── data/
│   ├── raw/                      ← train.csv, test.csv, sample_submission.csv
│   └── submissions/              ← submission_v1.csv (generated)
│
├── telco_churn/                  ← dbt project
│   └── models/
│       ├── staging/
│       │   ├── sources.yml       ← raw CSV source documentation
│       │   ├── stg_customers.sql ← rename, cast, normalize Yes/No → 1/0
│       │   └── schema.yml        ← column docs + data tests
│       ├── intermediate/
│       │   ├── int_churn_features.sql ← ALL feature engineering in SQL
│       │   └── schema.yml
│       └── marts/
│           ├── fct_churn_features.sql ← final ML feature mart
│           └── schema.yml
│
└── notebooks/
    └── churn_prediction.ipynb    ← EDA, 3 models, SHAP, submission
```

---

## Quick Start

```bash
# 1. Create and activate virtual environment
python3.13 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# 2. Run the dbt pipeline (from this directory)
dbt run   --project-dir telco_churn --profiles-dir .
dbt test  --project-dir telco_churn --profiles-dir .

# 3. Open and run the notebook
jupyter notebook notebooks/churn_prediction.ipynb
```

---

## dbt Layer (AE Differentiator)

**3 models, 108 data tests, all green.**

| Model                   | Rows    | Purpose                                     |
|-------------------------|---------|---------------------------------------------|
| `stg_customers`         | 594,194 | Rename → snake_case, cast types, binary norm |
| `int_churn_features`    | 594,194 | Feature engineering (9 derived features)    |
| `fct_churn_features`    | 594,194 | Final ML-ready mart                         |

### Engineered features (SQL-defined)

| Feature               | Logic                                          | Validated churn lift |
|-----------------------|------------------------------------------------|----------------------|
| `tenure_group`        | 0-12 / 12-24 / 24-48 / 48+ months             | 50% → 5% across cohorts |
| `contract_risk_score` | Month-to-month=3, One year=2, Two year=1       | Ordinal commitment signal |
| `charges_ratio`       | `monthly_charges / tenure_months`              | Cost-intensity per loyalty |
| `service_count`       | Sum of 6 internet add-on flags (0–6)           | Switching cost proxy |
| `has_any_streaming`   | StreamingTV OR StreamingMovies                 | Entertainment stickiness |
| `has_any_security`    | OnlineSecurity OR TechSupport                  | Security stickiness |
| `is_fiber_optic`      | `internet_service = 'Fiber optic'`             | High-cost, competitive tier |
| `is_electronic_check` | `payment_method = 'Electronic check'`          | Manual payment = low friction |
| `is_high_risk`        | M2M + Fiber optic + tenure < 12 months         | **71.2% churn rate** |

---

## ML Layer

Notebook: `notebooks/churn_prediction.ipynb`

- Reads from `main_marts.fct_churn_features` via DuckDB — **zero Python feature engineering**
- 3 models: Logistic Regression (baseline), XGBoost, LightGBM
- 5-fold stratified cross-validation, class imbalance handled
- Decision threshold tuned via Precision-Recall curve
- SHAP analysis: summary plot + waterfall plots for 3 customer archetypes
- Submission generated to `data/submissions/submission_v1.csv`

---

## Key Findings

- **is_high_risk customers (M2M + Fiber + <12mo tenure)**: 71.2% churn rate vs 14.8% baseline
- **Tenure effect is non-linear**: 50.4% churn in year 1 → 5.3% after 4 years
- **Contract type dominates**: Month-to-month customers are 3–5× more likely to churn than two-year customers
- **Service count reduces churn**: Each add-on is an incremental switching cost

---

## Competition

Yao Yan, Walter Reade, Elizabeth Park. *Predict Customer Churn*.
https://kaggle.com/competitions/playground-series-s6e3, 2026. Kaggle.
