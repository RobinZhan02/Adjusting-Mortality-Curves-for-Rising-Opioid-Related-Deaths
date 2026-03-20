# Adjusting Mortality Curves for Rising Opioid-Related Deaths Using Isotonic-Regression Frameworks

Shira Elmaliach, Amanda Huang, Angela Wang, Fan Ye, Zifeng Zhan

Supervised by Professor Gareth W. Peters

## Overview

This project investigates how opioid-related mortality has altered U.S. mortality patterns. We decompose observed mortality into three components: where the baseline is estimated via stochastic mortality models, the opioid component captures excess hazard, and covariates (behavioral risk factors, socioeconomic indices) enter through the observation equation.

### Models

- **Lee-Carter (LC):** Age-period model with a single time-varying mortality index.
- **Renshaw-Haberman (RH):** Extends LC with a cohort effect.
- **Cairns-Blake-Dowd (CBD):** Logit-based model with level and slope period factors, suited for older ages.

Models are fit at both national (HMD) and regional (CDC WONDER, four Census regions) levels. Monotonicity in the age effect is enforced via:

- **PAVA** (Pooled Adjacent Violators Algorithm) for isotonic regression
- **Expectation Propagation** with Gaussian process priors on virtual derivative observations

## Repository Structure

```
working code/                  Main analysis scripts
  combine_data_for_analysis_final.Rmd  Merge and format CDC WONDER data for modeling
  format_yearly_all_cause_to_stmomo.Rmd  Convert all-cause data to StMoMo format
  modeling.Rmd                         National-level mortality modeling (GAM, LC, RH, CBD)
  regional_analysis.Rmd                Regional LC/RH/CBD fits by Census region
  Regional_RHmodel.R                   Regional Renshaw-Haberman model fitting
  EP_PAVA.Rmd                          Isotonic regression via PAVA and EP-GP
  hmd_analysis.Rmd                     HMD-based national modeling and forecasting
  wonder_eda.Rmd / wonder_eda2/3.Rmd   Exploratory data analysis (CDC WONDER)
  wonder_time_series.Rmd               Dispersion and time-series analysis
  *.rds                                Cached model fits (LC, RH, CBD by region)

hmd/                           National HMD analysis outputs
  hmd_analysis.Rmd                     LC and RH modeling on HMD data
  *.csv                                Forecasted mortality rates (LC/RH, with CI bounds)
  ratio_*.csv / ratio_*_heatmap.png    Opioid-to-baseline mortality ratios
  sum_*.rds                            Annual model summary objects

Data/
  wonder_opioid/               CDC WONDER mortality extracts
    Five-Year-*.csv / Ten-Year-*.csv   Opioid deaths by age group, region, sex
    Census-Region*.csv                 Regional breakdowns
    allcause_stmomo_*.rds              Pre-formatted StMoMo data objects
  covariate/                   Covariate data and processing (didn't used in estimation due to time constraints)
    Behavioral_Risk_Factor_*.csv       BRFSS survey data
    covariate_combine_*.csv            Merged covariate panels (region/division)
    *_pre_whitening.csv                Pre-whitened covariate series
    socioeconomic_score.Rmd            SOA socioeconomic index construction
  missing_data/                Missing data inference
    Missing Data Infer Final.Rmd       Imputation for suppressed CDC counts
    Inferred-WONDER-*.csv              Completed datasets after inference
  time_series/                 Monthly/yearly time-series extracts

archive/                       Earlier exploratory work from prior quarters
```

## Data Sources

- **Human Mortality Database (HMD)** — National all-cause mortality and exposure data
  - https://www.mortality.org/
- **CDC WONDER Multiple Cause of Death (MCOD), 1999-2020** — Opioid-related and all-cause mortality by age, sex, race, region
  - https://wonder.cdc.gov/mcd.html
- **Behavioral Risk Factor Surveillance System (BRFSS)** — Health coverage and alcohol use prevalence by state/region
  - https://www.cdc.gov/brfss/
- **SOA Socioeconomic Index Score** — County-level socioeconomic scores from the Society of Actuaries
  - https://www.soa.org/resources/research-reports/2020/us-mort-rate-socioeconomic/

## Tools and Dependencies

- **R** with key packages: `StMoMo`, `demography`, `gnm`, `forecast`, `Iso`, `mgcv`, `tidyverse`
- **Docker** container available via `Dockerfile` and `devcontainer.json` for reproducibility
