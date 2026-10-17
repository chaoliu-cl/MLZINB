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
Hurdle conditions retain operational discovery frequencies but not a purported
ML-ZINB component-localization accuracy target.

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
Additional conditional-LR rules remove either the global gate or Holm correction,
so their incremental effects are separately evaluable using the same fitted models.
A nonsignificant valid global test ends the gated procedure without requiring the
two conditional fits to succeed. Separate additive tests report neither when both
fail to reject; only a supported omnibus gate can produce an unlocalized decision.

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

## Exact data generation and interpretation

Let w_ij = x_ij - mean_j(x) denote the focal within-cluster predictor, m_j its
cluster mean, z_j the context, and q_ij a Bernoulli(.45) control. Generate independent
standard-normal w values and subtract the realized cluster mean exactly. Set
m_j = .5*[r*z_j^* + sqrt(1-r^2)*Normal(0,1)], with r=0 except the composition
condition (r=.7). z_j is standard normal or Bernoulli(p); z_j^* uses its theoretical
standardization. Then x_raw = w + m. The conditional links are

    log(mu_ij) = .7 + .4*w_ij + a_c*z_j + .25*q_ij + .15*m_j
                 + .1*m_j*z_j + b_c*w_ij*z_j + u_cj + v_cj*w_ij + log(exposure_ij)
    logit(pi_ij) = -.55 - .8*w_ij + a_z*z_j + .35*q_ij + .15*m_j
                  + .1*m_j*z_j + b_z*w_ij*z_j + u_zj

The core uses NB2 size 1.4, u_c SD .35, u_z SD .50, and v_c=0; interactions
b_c/b_z follow the grid. Context main effects a_c/a_z are .15/.30, except the
null and NB conditions where they are zero. Null refers to the focal w-by-z
products: the adjusted m-by-z relationship is retained in every decomposed model.
NB truth sets pi=0 exactly, irrespective of the unused inflation link.

Unequal sizes are max(3, round(n*exp(.65*Normal(0,1)-.65^2/2))); sparse conditions
replace the first 20% by size 3. Informative sizes use the standardized count
intercept instead of an independent normal, inducing informative cluster size.
Correlated intercepts use the specified bivariate-normal correlation. Heavy tails
use a 90% N(0,1) / 10% N(0,9) mixture divided by sqrt(1.8), independently in both
components. Its exponential moments are finite, unlike Student-t log-count effects.
NB1 truth uses size=mu/1.4, so Var(Y|count state)=mu*(1+1.4). Hurdle truth draws
positive counts from the exactly zero-truncated NB and then inserts Bernoulli zeros.

Random count slopes have SD .30 and are independent of intercepts. Ordered-cluster
intercepts follow stationary Gaussian AR(1), rho=.60. Within-cluster serial shocks
have SD .35 and AR(1) rho=.60 and enter the count link. Variable exposure is
exp(Normal(0,.6^2)); variable NB2 size is 1.4*exp(.4*w+.25*z). All other changes
are defined by the saved condition grid, not chosen after examining results.

The independent reference contains 96 covariate profiles, normal w/z clipped to
[-2.5,2.5], and newly generated cluster means/controls/exposures. It represents
uniformly sampled new clusters, including under informative size. Its prediction
target is not the distribution of a size-weighted sampled individual. Expected
outcome and total-zero probabilities integrate BOTH component intercepts, and the
count slope/shock variance when present. Fitted models integrate their own fitted
random-effect distribution; setting a random intercept to zero is not marginalization.
Use 13-point normal quadrature (25 per mixture component for heavy-tail truth),
checked against 41 points. The independent score is MSE against known population
targets; it avoids the noise from a single realized test count.

The marginal latent count-process intensity E(mu), E(pi), E(Y), and P(Y=0) are four distinct
targets. With correlated component intercepts, E(Y) is not generally
(1-E(pi))*E(mu). For hurdle truth we deliberately suppress count-state/inflation
recovery because those latent meanings differ. Under misspecified models, generating
coefficient coverage is a recovery diagnostic, not guaranteed pseudo-true coverage.
The undecomposed predictor's coefficient is not assigned the within-cluster target.
With correlated component intercepts, E(mu) is also not generally E(Y | S=0)
after marginalization: the latter reweights clusters by their nonstructural probability.

The response contrast is [E(Y|w=1,z=high)-E(Y|w=-1,z=high)] minus the corresponding
low-context difference, averaged over q with weights .55/.45 at m=0 and exposure=1.
Apply the same cross difference to all four targets. Nonlinear links can produce
a nonzero response contrast even if the focal link-scale products are absent.
Report its actual generated value, not a null hypothesis imposed by the product terms.

Production uses 29,000 paired datasets at 500 per each of 58 conditions. The minimum
candidate workload is 265,500 fits (before optimizer retries), including matched
random-slope models and the undecomposed comparator. Model fitting dominates runtime;
the complete production computation can take several days on two workers.
