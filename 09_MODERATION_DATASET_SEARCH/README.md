# Supported social-science example: Capital Bikeshare

Start with [the complete HTML report](walkthrough_report.html) or [Markdown report](walkthrough_report.md). The selected application analyzes casual rental counts in 15,720 hourly records nested within 655 complete days. Working-day context modifies the within-day clock-time profile. The frozen revised model is evaluated separately in 2011 and 2012, with day-cluster and calendar-HAC uncertainty.

The search is visible. The German health-panel question failed the discovery joint test; a midday-only Bikeshare specification had a poorly identified inflation interaction. Both are retained. The final smooth daily-profile model was frozen before its 2012 interaction results were examined. This is exploratory model development with temporal validation in one system.

## Reproduce the selected application

From the publication-bundle root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "09_MODERATION_DATASET_SEARCH/code/run_profile.ps1"
```

Existing fits and diagnostic objects are reused by default. Run with `-Recompute` after changing data, formulas, source versions or protocol. This archives only the selected application’s outputs and figures under `bikeshare_profile/`; it preserves source downloads, failed candidates and all original study files. Full recomputation is substantial.

Dependencies: R with glmmTMB, lme4, DHARMa; Python with pandas, numpy, scipy, requests, beautifulsoup4 and matplotlib. A local Markdown renderer is included under code/vendor. R defaults to `C:/Program Files/R/R-4.4.2/bin/Rscript.exe` and can be supplied through `-ProfileRscript`. Package/session information is retained in the outputs.

## File map

| Location | Purpose |
| --- | --- |
| walkthrough_report.html / .md | Main results, diagnostics, interpretation and sources |
| download_manifest.json | Source URLs, timestamps, byte counts and SHA-256 hashes |
| search_protocol.md | Initial candidate protocol and source corrections |
| bikeshare_profile/protocol.md | Final daily-profile question, frozen temporal validation and sensitivity plan |
| bikeshare/source/ | UCI archive, metadata, source documentation, original hourly and daily CSV files |
| bikeshare_profile/outputs/analysis_data.csv | Balanced primary data, with explicit date and group keys |
| bikeshare_profile/outputs/models/ | Four matched ML-ZINBs plus NB comparator, separately by sample |
| bikeshare_profile/outputs/*interaction_tests.csv | Likelihood-ratio comparisons with actual dimensions |
| bikeshare_profile/outputs/score_inputs/ | Design matrices, full nuisance-inclusive covariance and marginal modes |
| bikeshare_profile/outputs/*score_verification.json | Independent likelihood and score reconstruction against glmmTMB |
| bikeshare_profile/outputs/*HAC_joint_tests.csv | Joint and component tests at 7-, 14- and 28-day calendar lags |
| bikeshare_profile/outputs/component_predictions.csv | Four quantities at each hour/day type, with pointwise calendar-HAC intervals |
| bikeshare_profile/outputs/diagnostics/ | Unconditional simulations, residual tests and calibration |
| bikeshare_profile/outputs/sensitivity_models/ | Flexible time bases, random structures, coverage and optimizer variants |
| bikeshare_profile/outputs/exact_deletion_audit.csv | Exact refits for selected influential and fixed-calendar days |
| bikeshare_profile/figures/ | Scientific PNG/PDF figures, including the main component predictions |
| outputs/bundle_verification.json | Data, numerical and artifact checks; not a claim of model perfection |
| rwm/ | German health-panel source audit and nonsupportive discovery models |
| bikeshare/outputs/models/ | Rejected midday-specification fits; not the selected profile models |
| countymurders/ | Downloaded/documented geographic alternative, never outcome-modeled |

The primary count time basis has four products with context, the inflation basis has two, and their joint test has six df. Do not relabel it as the two-df scalar test used in the earlier VLSS example. Full-sample pooling adds a year indicator; separate-year fits omit a constant year term.

All component predictions form mixtures recordwise, then average over the empirical reference distribution. They set day random effects to zero and do not integrate over their distribution. The group sandwich includes dispersion and random-intercept uncertainty, and the calendar-HAC calculation retains gaps in calendar time.

The main uncertainty method is the independently verified sandwich/HAC calculation. No full refit cluster bootstrap is claimed. Influence is approximated for all days, followed by exact refits for selected dates. Saved audit files distinguish numerical convergence, weak component estimation and residual fit.

The additional clock-time/context dispersion sensitivity was added because primary simulations overpredicted extreme counts. Its [adequacy amendment](bikeshare_profile/adequacy_amendment.md) and the complete diagnostic outputs are retained. It improves zero calibration, but upper-tail discrepancies remain. The added inflation random intercept collapses to nearly zero with a failed Hessian and is excluded from inference.

## Source and scope

[UCI Bike Sharing dataset](https://archive.ics.uci.edu/dataset/275/bike+sharing+dataset), DOI 10.24432/C5W894, explicitly categorized as Social Science and licensed CC BY 4.0. Cite Fanaee-T and Gama (2013), DOI 10.1007/s13748-013-0040-3. The original source is Capital Bikeshare's Washington DC operational data. The original study's other datasets were preserved.

This is a day-context human-mobility example. It does not establish causal moderation, neighborhood effects, a real latent non-user class or external validity to other systems. The report retains remaining adequacy issues and model-selection history.
