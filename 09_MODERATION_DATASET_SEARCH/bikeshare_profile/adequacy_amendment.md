# Diagnostic-driven dispersion sensitivity

Added after all discovery and validation primary tests, when 500 pooled primary-model simulations showed excessive upper-tail counts (observed maximum 367 versus simulation median 907), too much overall variance, and a modest zero-count discrepancy. This was not used to choose the validated primary interaction or its p-value.

Fit an additional full-sample sensitivity with the same count and inflation means and day random intercept, but NB2 dispersion modeled as a log-linear function of workingday and the first two clock-time harmonics. It allows the mean-variance relationship to differ across the day and day type. Inspect numerical identification, AIC, component product Wald tests and 500 unconditional simulations. Treat this as secondary model refinement, not independent validation. Do not replace an unfavorable diagnostic by showing only favorable ones.
