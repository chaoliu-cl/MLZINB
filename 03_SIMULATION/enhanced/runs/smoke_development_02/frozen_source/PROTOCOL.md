# Enhanced component-aware ML-ZINB simulation

Implementation protocol, 16 October 2026; frozen by hash at production launch.
Existing simulations are preserved.

## Aim and estimands

Assess the complete decision workflow, component localization, estimation, uncertainty,
out-of-sample prediction, and numerical reliability. This is a prospective simulation
amendment informed by empirical applications; it is not retrospective preregistration.
The count interaction and inflation interaction are distinct link-scale estimands.
An absent inflation interaction is never inferred merely from p > .05.

## Design

Retain the original 22-condition core: seven truth types, active interaction magnitudes
0.15/0.30, and 40 x 30 or 80 x 60 balanced clusters. Revise the focal predictor to its
within-cluster deviation and explicitly include its cluster mean, so a within-context
estimand is defined. Core means are approximately two counts and the NB2 size is 1.4;
count/inflation random-intercept SDs are 0.35/0.50.

Add targeted conditions, not a full factorial: cluster number and size separately
(including 20 and 160 clusters), unbalanced/sparse and informative cluster sizes,
low/high extra-zero probabilities, approximately low observed-zero counts with larger
means, weak/strong dispersion, unequal component effects, binary/imbalanced context,
predictor-composition correlation, correlated cross-component intercepts, random slopes,
variable exposure, omitted decomposition, variable dispersion, heavy-tailed random
effects, NB1 count truth, hurdle truth, serial cluster effects, and within-cluster serial shocks.
Include absent, weak and strong inflation random effects (SD 0, .15 and .9).
There are 58 conditions: 22 core and 36 targeted stress conditions.
The generated grid is the definitive exhaustive list. Report empirical zero rates,
not only intended structural-zero probabilities. Latent-component recovery is undefined
for hurdle truth; inflation-interaction recovery is undefined for NB truth.

Default production repetitions: 500 per condition. At true p=.05/.95 the binomial
MCSE is about .00975; at .50 it is .02236. Report uncertainty around Monte Carlo rates
and do not advertise .005 precision. Repetition counts can be raised prospectively.
There is no outcome-dependent stopping. Smoke runs are labelled and never pooled into
production results. Deterministic seeds identify condition and replication without
collisions up to 100,000 repetitions, independent of worker count or resume order.

## Candidates and workflow comparisons

Nine core candidate models: NB additive; NB with count moderation; ZINB with intercept-
only inflation; ZINB with only an inflation random intercept; additive ZINB; count-only,
inflation-only and joint moderation ZINBs; and joint ZINB with fixed inflation covariates
but no inflation random intercept. All include the same count controls and offset.
Four matched random-count-slope ZINBs are additionally fit in random-slope conditions;
an undecomposed joint ZINB is additionally fit in the composition-correlation condition.

The primary component rule uses four matched ZINBs: test additive versus joint (2 df)
at .05, then Holm-adjust the two conditional 1-df additions from the joint model.
Possible outputs: neither, count, inflation, both, unlocalized (global supported but
neither conditional test supported), and numerical failure. Report unconditional and
valid-fit conditional performance separately. Compare this rule to count-only testing,
separate unadjusted additive tests, AIC among the matched four, AIC among all candidates,
and gated joint-Wald component rules with model, cluster sandwich and ordered-cluster
Bartlett-HAC covariance. AIC is a prediction-oriented alternative, not a .05 test.
NB-versus-ZINB chi-square boundary tests are not used.

## Uncertainty

Model covariance and full-parameter cluster marginal-likelihood scores are computed
for valid joint fits. Scores include nuisance parameters. The score sum is checked
against the package gradient. Cluster covariance uses G/(G-1); HAC uses ordered
cluster scores with Bartlett lag floor(4*(G/100)^(2/9)), minimum 1. HAC across unordered
independent clusters is a calibration comparison only. Report normal Wald component
intervals/tests and chi-square joint tests; their finite-cluster calibration is itself
an outcome. Robust covariance does not repair misspecified estimands or latent classes.

## Predictions

Evaluate on an independently seeded covariate reference set for new clusters,
integrating the random-effect distribution with fixed Gauss-Hermite quadrature.
Record MSE for count mean, inflation probability, overall mean and total zero probability.
Also evaluate the response-scale difference-in-differences for x=-1/+1 and context=-1/+1
(0/1 for binary context), averaged over the same binary-control reference distribution.
Use delta-method intervals from model and robust covariance. Under misspecification,
observable mean/zero predictions remain evaluable; latent-component scores are omitted
where their substantive target is undefined. Compare algorithms on paired datasets.

## Numerical acceptance and failures

Require optimizer status zero, positive-definite finite covariance and Hessian, maximum
Newton correction <.01 parameter SEs, and Newton decrement <.01. Save warnings, gradients,
largest coefficient/SE, boundary SDs, attempts, timing and errors. Retry the identical
formula with BFGS after default optimizer failure. Never silently simplify a failed fit.
No parameter, prediction or likelihood-ratio inference uses rejected fits. Save failures
as outcomes; do not simulate replacements until an arbitrary successful-fit quota is met.
The first replicate of every condition is retained with fits for independent checks.

## Reporting and execution

Checkpoint each paired replication atomically, including all valid and failed models.
Hash source and freeze configuration before launch; reject resumes after source/config
changes. Save R/session versions and independent verification. Aggregate completed and
planned denominators, Monte Carlo intervals, paired algorithm comparisons, raw data,
numerical failure tables and publication figures. A run is complete only when every
planned condition/replication has a verified checkpoint; partial runs are labelled.
The Windows launcher runs hidden, supports resume, and logs progress. Checkpoints are
small result objects, not a copy of every large fitted model.
