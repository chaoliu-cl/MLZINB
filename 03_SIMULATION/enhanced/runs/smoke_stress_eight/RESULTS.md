# Enhanced ML-ZINB simulation results

Status: All planned checkpoints completed without pipeline errors.
Mode: smoke. 8/8 paired datasets checkpointed across 8 conditions; 0 pipeline errors.

**These are execution/provisional results, not final publication evidence.**

The original pilot is preserved. Candidates share each generated dataset and all comparisons are paired.
Inference uses accepted fits only. Completed-denominator workflow rates count failures as no discovery; valid-workflow rates exclude them. Pending datasets are not silently treated as failures.
Under NB truth, inflation claims are operational overclaims, not a regular identifiable-parameter type-I error. Under hurdle truth, only observable mean/zero targets and operational discovery frequencies are compared; component-localization accuracy is undefined.
Response-scale cross differences can be nonzero without a link-scale product; their coverage targets the generated cross difference, not an assumed zero.
Robust intervals address score covariance; they do not repair omitted structure or redefine a latent component.

See `tables/` for denominators, MCSEs, Wilson Monte Carlo intervals, paired differences, parameter/contrast recovery, and numerical reliability.
See `raw/` for compressed replication-level records, `figures/` for PNG/PDF graphics, and `frozen_source/` for the exact implementation.
