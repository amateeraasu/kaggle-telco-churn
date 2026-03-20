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
| `int_churn_features`    | 594,194 | Feature engineering (16 derived features)   |
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
- 3 base models: Logistic Regression, XGBoost, LightGBM + 3-model blend + Optuna-tuned XGBoost
- 5-fold stratified cross-validation, class imbalance handled per model
- Decision threshold tuned via Precision-Recall curve (maximise F1)
- Optuna: 50 trials × 3-fold CV, XGBoost only
- Probability calibration: Platt scaling (MCE 0.1920 → 0.0444)
- SHAP analysis: summary plot + waterfall plots for 3 customer archetypes
- Submissions: `data/submissions/submission_v1.csv`, `submission_v2.csv`

### v1 Model Results (43 features)

| Model               | CV AUC          | Test AUC   | Test F1    |
|---------------------|-----------------|------------|------------|
| Logistic Regression | 0.9111 ± 0.0009 | 0.9116     | 0.6948     |
| XGBoost             | 0.9157 ± 0.0010 | **0.9163** | **0.7029** |
| LightGBM            | 0.9156 ± 0.0010 | 0.9161     | 0.7021     |

---

## v2 Improvements (47 features)

### New Features Added

| Feature                    | Logic                                      | What it captures |
|----------------------------|--------------------------------------------|-----------------|
| `charges_diff`             | `total_charges − (monthly_charges × tenure)` | Negative = billing anomaly or discount applied; discounted customers churn post-promotion |
| `is_total_charges_missing` | `1` if `total_charges` is null or zero     | Brand-new customers (<1 month billed); highest short-term churn cohort |
| `tenure_decay`             | `1 / (tenure_months + 1)`                 | Convex transform of tenure's non-linear churn curve; directly usable by Logistic Regression |
| `payment_friction`         | `is_electronic_check × is_high_risk`       | Explicit interaction: manual-pay + worst-case profile; gives LR the compound signal trees discover via splits |

### v1 → v2 AUC Comparison

| Model                           | v1 AUC  | v2 AUC     | Δ       |
|---------------------------------|---------|------------|---------|
| Logistic Regression             | 0.9116  | **0.9121** | +0.0005 |
| XGBoost                         | 0.9163  | 0.9164     | +0.0001 |
| LightGBM                        | 0.9161  | 0.9162     | +0.0001 |
| Blend (LR×0.2 + XGB×0.4 + LGB×0.4) | —   | 0.9163     | —       |
| XGBoost (tuned — Optuna 50T)    | —       | 0.9165     | —       |

LR gains most from explicit interaction terms; tree models already discover these via splits.
Optuna best params (depth=4, lr=0.089) matched default AUC — original params were near-optimal.
Platt calibration: MCE **0.1920 → 0.0444** (77% reduction) — used for submission_v2.csv.

### Submission v2

`submission_v2.csv` uses **Platt-scaled LightGBM** probabilities.
Mean predicted churn: **0.2183** | Range: [0.0132, 0.8262]

---

## Key Findings

- **is_high_risk customers (M2M + Fiber + <12mo tenure)**: 71.2% churn rate vs 14.8% baseline
- **Tenure effect is non-linear**: 50.4% churn in year 1 → 5.3% after 4 years
- **Contract type dominates**: Month-to-month customers are 3–5× more likely to churn than two-year customers
- **Service count reduces churn**: Each add-on is an incremental switching cost
- **charges_diff as discount detector**: Negative values flag promotional pricing — a short-term retention tactic that correlates with higher post-promotion churn
- **Calibration matters for business use**: Raw model probabilities (MCE=0.19) overstated churn probability; Platt scaling corrected this (MCE=0.04), making predicted P=0.30 actually mean ~30% churn rate

---

## Competition

Yao Yan, Walter Reade, Elizabeth Park. *Predict Customer Churn*.
https://kaggle.com/competitions/playground-series-s6e3, 2026. Kaggle.
