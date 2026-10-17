# Implementation of the enhanced simulation

16 October 2026. The original pilot and manuscript files are preserved.

## What the new study evaluates

The implementation tests the practical value and limits of **component-aware
evaluation of contextual moderation in ML-ZINB**. The interaction in the log count
intensity and the interaction in the structural-zero logit are separate estimands.
The simulation evaluates both links and the combined response, rather than judging
the approach solely by AIC or by whether one product has p < .05.

| Question for the manuscript | Evidence the simulation produces |
|---|---|
| Does moderation exist? | Omnibus rejection rates under null and active scenarios, with completed and valid-test denominators |
| Which component supports it? | Exact localization, count/inflation claims, false-component claims, global-only/unlocalized outcomes and confusion tables |
| Does the gate or multiplicity adjustment help? | Paired comparisons with gate/correction ablations, separate additive tests, count-only testing and AIC |
| Are estimated effects trustworthy? | Bias, RMSE, empirical SD, average SE, SE ratio, 95% coverage and wrong-sign frequencies |
| Is the distinction substantively useful? | Four independent population prediction errors and response-scale cross differences; paired costs of omitting either interaction |
| Do practical design problems matter? | Separate cluster-number/size changes, sparse and unequal clusters, binary context imbalance, weak inflation identification and composition correlation |
| Can robust inference rescue omitted structure? | Model, full-parameter cluster and ordered-cluster HAC comparisons; matched random-slope fits distinguish variance adjustment from structure adjustment |
| When should the procedure be qualified? | NB and hurdle truth, correlated or heavy-tailed effects, informative size, serial dependence, NB1 and varying dispersion, and explicit numerical failures |

The primary workflow compares four nested ZINBs with the same observations, offset,
controls and random-intercept structure. It tests additive versus joint (2 df),
then uses Holm-adjusted conditional count and inflation additions (1 df each).
“Neither supported,” “unlocalized,” and “numerical failure” remain different outputs.
AIC and robust Wald alternatives are evaluated as comparators, not treated as
equivalent .05 tests.

## Planned production computation

There are **58 prespecified conditions**, comprising the revised 22-condition core
and 36 targeted extensions. The frozen default is **500 repetitions per condition**:
**29,000 paired datasets and 265,500 candidate fits before optimizer retries**.
Randomness is deterministic and independent of scheduling. No replications are
replaced to reach a successful-fit quota or a desired empirical conclusion.

At a rate of .05 or .95, 500 repetitions imply MCSE about .00975; at .50, about
.02236. Every reported rate includes its denominator and Monte Carlo uncertainty.
These are design precision calculations, not results from a completed production run.

The first production repetition exercises every condition before proceeding to
later repetitions. Unexpected pipeline errors halt progression; rejected model
fits remain simulation outcomes. Per-dataset atomic checkpoints, frozen source,
configuration hashes, package/R versions, per-model worker progress and resume
checks support a long local computation. On this computer it is a multiday job.

## Verification and important corrections

The independent verification suite passed **137 checks**, including all 58 data
generators and finite truth targets, new-group prediction links and offsets,
quadrature accuracy, component classification, cluster-score identity, numerical
delta derivatives, random-slope parameter ordering, matched sample sizes,
reporting denominators, all four prediction targets and unchanged checkpoint resume.
The score-sum discrepancy in the benchmark was below 6e-11; the new-group inflation
prediction discrepancy was below 4e-16; the delta derivative discrepancy was below
2e-8. These establish implementation consistency, not Monte Carlo calibration.

Targeted execution runs also exercised binary context, composition, random slopes,
heavy tails, NB1, hurdle outcomes, and both types of serial dependence. Reporting
was checked for core-only and stress-only runs. The retained one-repetition
execution results are explicitly labelled and must not be used as power, type-I
error or coverage evidence.

Several methodological safeguards matter:

- Predictions use independent covariate profiles for new clusters and explicitly
  integrate both fitted random-effect distributions. They do not reuse training
  outcomes or treat zero random effects as marginalization.
- Heavy-tailed count effects use a finite-moment normal mixture. Student-t effects
  on the log count scale would make the population count mean infinite.
- The full nuisance-parameter score covariance is used for robust response-scale
  intervals, with parameter ordering and score sums checked.
- Under NB truth, inflation recovery is undefined and inflation claims are
  operational overclaims. Under hurdle truth, ML-ZINB component-localization
  accuracy and latent-component recovery are suppressed; observable mean/zero
  predictions and operational discovery frequencies remain evaluable.
- E(mu), E(pi), E(Y) and P(Y=0) are distinct targets. With correlated component
  effects, E(Y) need not equal (1-E(pi))*E(mu), and E(mu) is not generally the
  marginal mean conditional on belonging to the nonstructural state.
- Nonlinear links can create response-scale cross differences without a focal
  link-scale interaction. Contrast recovery uses the actual generated contrast.
- False-component tables concern the probability of a false component claim;
  they are not an estimate of a Benjamini-Hochberg false discovery rate.

## Where to find the work

- `PROTOCOL.md`: exact design, equations, estimands, inference and failure rules.
- `simulation.R`: data generation, fitting, component tests, population prediction,
  uncertainty calculations and atomic paired-dataset checkpoints.
- `run.R` and `launch.ps1`: frozen configuration, dynamic scheduling, production
  first-sweep safeguard, hidden execution and resumption.
- `summarize.R`: raw records, Monte Carlo summaries, paired comparisons and PNG/PDF
  figures, including component omission cost and cluster number versus size.
- `verification/`: independent check results, software environment and benchmark.
- `runs/production_2026-10-16/`: the production computation; use its live status and
  checkpoint count to determine completion, not this dated implementation note.

See `README.md` for commands. Final production tables and figures are written
automatically after the configured computation finishes. Until all planned
checkpoints are present without pipeline errors, do not describe the production
simulation as completed or infer a favorable methodological conclusion from the
execution checks. The established statistical tools used here are not claimed as
new tests; the proposed contribution is their component-aware evaluation and
practical interpretation.
