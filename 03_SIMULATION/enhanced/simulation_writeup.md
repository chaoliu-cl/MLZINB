# Enhanced simulation study: component-aware evaluation of contextual moderation in ML-ZINB models

## Purpose

The simulation evaluates a complete decision process for contextual moderation in
multilevel zero-inflated negative-binomial (ML-ZINB) models. The central distinction
is between moderation of the conditional count intensity and moderation of the
structural-zero probability. These are separate parameters, and a useful evaluation
must determine whether moderation is supported, identify the component carrying the
evidence, quantify the consequences of omitting a component, and check numerical and
predictive reliability.

The simulation therefore evaluates the proposed component-aware workflow against
simpler testing, AIC selection, and Wald-based alternatives. It also examines the
conditions under which a component-aware conclusion becomes unreliable: weak
inflation identification, few clusters, unbalanced cluster sizes, random slopes,
correlated random effects, dependence, and distributional misspecification.

## Methods

### Design and estimands

The study has 58 prespecified conditions: 22 core conditions and 36 targeted stress
conditions. The core varies seven focal moderation truths—null, additive context,
negative-binomial truth, inflation-only, count-only, dual same-sign, and dual
opposite-sign moderation—over interaction magnitudes 0.15 and 0.30 where applicable,
and over designs with 40 clusters of 30 observations or 80 clusters of 60
observations. The stress grid varies one design feature at a time or adds a targeted
misspecification. It includes 20 and 160 clusters, larger clusters, unequal and
sparse cluster sizes, informative cluster size, low or high extra-zero prevalence,
weak or strong overdispersion, unequal component effects, binary and imbalanced
contexts, predictor-composition correlation, positive and negative correlation
between component random intercepts, absent/weak/strong inflation heterogeneity,
random count slopes, exposure heterogeneity, varying dispersion, finite-moment
heavy-tailed random effects, NB1 truth, hurdle truth, ordered-cluster dependence,
and within-cluster serial dependence.

The primary estimands are the focal within-cluster-by-context products in the two
links. Let (w_{ij}=x_{ij}-\bar{x}_j) be the within-cluster predictor deviation,
(m_j=\bar{x}_j) the cluster mean, and (z_j) the cluster context. The count
interaction is (b_c) in the log conditional count-intensity model. The inflation
interaction is (b_z) in the logit structural-zero model. The simulation does not
interpret a nonsignificant estimate in one component as evidence that the other
component is absent.

### Data-generating process

For observation (i) in cluster (j), the generating links are

\[
\begin{aligned}
\log(\mu_{ij}) &= 0.70+0.40w_{ij}+a_cz_j+0.25q_{ij}+0.15m_j
 +0.10m_jz_j+b_cw_{ij}z_j+u_{cj}+v_{cj}w_{ij}+\log(e_{ij}),\\
\operatorname{logit}(\pi_{ij}) &= -0.55-0.80w_{ij}+a_zz_j+0.35q_{ij}+0.15m_j
 +0.10m_jz_j+b_zw_{ij}z_j+u_{zj},
\end{aligned}
\]

where (q_{ij}\sim\mathrm{Bernoulli}(0.45)), (e_{ij}=1) in the core and is
log-normal in the variable-exposure condition. The core uses (a_c=0.15),
(a_z=0.30), NB2 size 1.4, count random-intercept SD 0.35, and inflation
random-intercept SD 0.50. The null and NB conditions set the focal products to zero;
the NB condition sets (pi_{ij}=0) exactly. The count and inflation interaction
values follow the condition grid, including same-sign and opposite-sign pairs.

The focal predictor is generated within cluster and centered exactly, while its
cluster mean is included in every decomposed model. This defines the target as a
within-context effect and prevents a between-cluster predictor composition from
being mistaken for contextual moderation. The composition condition correlates
(m_j) with (z_j). Correlated component random intercepts use the specified
bivariate-normal correlation. Random-slope conditions add an independent count
slope with SD 0.30.

Counts are generated from an NB2 distribution unless the condition specifies NB1,
which uses size (mu/1.4). Hurdle conditions generate positive counts from an
exactly zero-truncated NB distribution and then insert Bernoulli zeros. The
heavy-tailed condition uses a 90% (N(0,1))/10% (N(0,9)) mixture divided by
(\sqrt{1.8}). This provides heavy tails while retaining finite exponential
moments; a Student-(t) random effect on the log-count scale would not have a
finite marginal count mean.

### Candidate models

Nine base candidates are fitted to each generated dataset:

1. additive ZINB;
2. count-interaction ZINB;
3. inflation-interaction ZINB;
4. joint count-and-inflation-interaction ZINB;
5. additive NB;
6. count-interaction NB;
7. intercept-only inflation ZINB;
8. random-inflation-intercept-only ZINB; and
9. joint ZINB with fixed inflation covariates but no inflation random intercept.

All comparable candidates use the same controls, offset, data, and random-intercept
structure. Matched random-count-slope versions of the four focal ZINB models are
added in random-slope conditions. An undecomposed joint model using the raw
predictor is added in the composition-correlation condition.

### Component-aware workflows

The primary workflow compares four matched ZINBs. It first tests additive versus
joint moderation with a two-degree-of-freedom likelihood-ratio test at 0.05. If the
omnibus test is supported, it tests the count and inflation additions separately
with one-degree-of-freedom likelihood-ratio tests and Holm adjustment. The result is
classified as:

- **neither:** no supported moderation;
- **count:** only the count component is supported;
- **inflation:** only the inflation component is supported;
- **both:** both components are supported;
- **unlocalized:** the omnibus test is supported but neither conditional test is
  supported after adjustment; or
- **failure:** the relevant likelihood comparison is unavailable because a required
  fit failed numerical acceptance.

The study also fits ablations that remove the omnibus gate or Holm adjustment,
separate unadjusted additive tests, a count-only workflow, AIC among the matched
four models, AIC among all available candidates, and joint Wald tests using model,
cluster-sandwich, and ordered-cluster Bartlett-HAC covariance. These are comparison
procedures rather than interchangeable definitions of a component-aware decision.

### Numerical acceptance and uncertainty

A fit is accepted only when the optimizer reports success, the covariance and Hessian
are finite and positive definite, the maximum Newton correction is below 0.01
parameter standard errors, and the Newton decrement is below 0.01. Each formula is
first fitted with the default optimizer and then retried with BFGS if necessary.
Rejected fits are retained as failures and are never silently replaced by a simpler
model.

For accepted joint fits, the simulation computes full-parameter marginal-likelihood
cluster scores, including nuisance parameters. The score sum is checked against the
package gradient. Cluster covariance uses the finite-cluster multiplier (J/(J-1)).
An ordered-cluster Bartlett-HAC covariance is also calculated; it is a calibration
comparison when clusters are independent and unordered. Delta-method intervals are
calculated for response-scale contrasts using model, cluster, and HAC covariance.

### Prediction evaluation

Prediction is evaluated on an independently seeded reference sample representing new
clusters. The reference contains 96 covariate profiles, with predictors and contexts
bounded to ([-2.5,2.5]). Population targets integrate the fitted or generating
random-effect distributions with Gauss-Hermite quadrature rather than setting random
effects to zero. Four targets are recorded separately:

1. latent count-process intensity (E(\mu));
2. structural-zero probability (E(\pi));
3. overall expected count (E(Y)); and
4. total-zero probability (P(Y=0)).

The study also evaluates a response-scale difference-in-differences comparing
(w=-1) and (w=1) across low and high context, averaged over the binary control.
The actual generated contrast is used as the target. This matters because nonlinear
links can produce a response-scale contrast even when a particular link-scale
interaction is absent. Latent component recovery is omitted for NB truth and hurdle
truth; observable mean and zero predictions remain evaluable.

### Monte Carlo plan and computation

The planned production run contains 500 repetitions per condition, or 29,000 paired
datasets. The minimum workload is 265,500 candidate fits before optimizer retries.
The same generated dataset is shared by all candidate models and workflows. Seeds
are deterministic and independent of worker order. Each replication is written to an
atomic checkpoint containing data diagnostics, fit status, estimates, decisions,
predictions, robust-inference diagnostics, and elapsed time. The first replication
of every condition retains fitted objects for independent checks.

For a rate near 0.05 or 0.95, 500 repetitions give an approximate binomial Monte
Carlo standard error of 0.00975; for a rate near 0.50, the corresponding value is
0.02236. Results are therefore reported with Monte Carlo standard errors and Wilson
intervals. The implementation does not claim 0.005 precision from 500 repetitions.

## Results

### Verification and execution results available at the time of writing

The independent verification suite passed all 137 checks. These checks covered all
58 data-generating conditions, finite population targets, exact within-cluster
centering, seed uniqueness, zero-random-effect mixture identities, 13- versus
41-point quadrature, the prediction engine for genuinely new cluster levels,
full-parameter score identities, delta-method derivatives, random-slope parameter
ordering, classification rules, reporting denominators, and unchanged checkpoint
resumption. In the benchmark fit, the maximum discrepancy between the full cluster
score sum and the package gradient was (5.9\times10^{-11}). The independent
new-group inflation prediction discrepancy was below (4\times10^{-16}), and the
finite-difference check of the delta gradient had maximum discrepancy below
(2\times10^{-8}).

Targeted one-replication execution checks completed without pipeline errors for
binary context, predictor-composition correlation, random slopes, variable
dispersion, finite-moment heavy tails, NB1 truth, hurdle truth, and serial
dependence. These runs demonstrate that the stress branches, failure accounting,
prediction targets, and reporting code execute. They are deliberately not used as
estimates of power, type-I error, coverage, or model-selection accuracy.

### Current production status

The production run `production_2026-10-16` has completed the first replication in
all 58 conditions without pipeline errors and has begun replication 2. At the time
of this writeup, the run is therefore an active computation rather than a completed
Monte Carlo study. The checkpoint and progress files are the authoritative status
record.

The following operating characteristics are intentionally not reported yet:

- rejection rates and power under active moderation;
- type-I error under null moderation;
- component-localization accuracy and false-component rates;
- parameter bias, RMSE, standard-error calibration, and coverage;
- prediction MSE and response-contrast coverage; and
- comparative performance of the primary workflow, AIC, separate tests, and Wald
  alternatives.

Reporting these quantities from the first replication or from the targeted smoke
runs would give them no meaningful Monte Carlo precision and could make a numerical
execution check look like evidence for the methodological claim. Once the 29,000
planned checkpoints are complete, `summarize.R` will create the final tables for
these quantities, paired workflow differences, numerical failure rates, and the
publication figures.

### Interpretation of the eventual results

The final results should be interpreted in four layers. First, the null and NB
conditions determine whether the workflow controls false localization and whether
inflation claims arise when the latent inflation component is undefined. Second,
the count-only, inflation-only, same-sign, and opposite-sign conditions determine
whether moderation is detected and assigned to the correct component. Third, the
stress conditions show how the decision changes with cluster number, cluster size,
context support, random-effect structure, dependence, and distributional
misspecification. Fourth, the independent prediction targets show whether a
component-aware conclusion improves the observable mean and zero predictions that
matter in applied work.

Numerical failure is treated as an outcome distinct from “neither supported.” A
valid nonsignificant component test is not interpreted as proof of no moderation.
Similarly, a global rejection without a supported conditional addition remains
unlocalized. Under NB truth, an inflation discovery is an operational overclaim,
not a regular type-I-error event for an identifiable inflation parameter. Under
hurdle truth, component-localization accuracy is undefined because the generating
zero process does not have the same ML-ZINB latent interpretation.

## Reproducibility files

The implementation is in [`simulation.R`](simulation.R), with execution in
[`run.R`](run.R) and [`launch.ps1`](launch.ps1), aggregation in [`summarize.R`](summarize.R),
and independent checks in [`verify.R`](verify.R). The exact design and equations are
in [`PROTOCOL.md`](PROTOCOL.md). The current production run is under
`runs/production_2026-10-16/`. The original simulation remains unchanged elsewhere
in the bundle.

## Manuscript reporting note

The methods text above can be used in the manuscript after the final production
aggregation. The Results section should be updated from the generated files in
`runs/production_2026-10-16/tables/` and `figures/`, and should report the completed,
valid-fit, and planned denominators together with Monte Carlo intervals. Until the
run reaches `complete` with zero pipeline errors, the present document should be
described as an implementation and execution report, not as the final simulation
evidence for the proposed component-aware evaluation.
