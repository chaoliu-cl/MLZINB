# CCD and NNCS: refits with clearer multilevel structure

This report gives new fits of the previously selected moderators. The primary changes were specified in [the analysis protocol](protocol.md) before fitting; the additional CCD inflation random-slope check and numerical implementation changes are documented there separately. Original inputs and prior results were preserved.

CCD retains the opposite-sign pattern after the structural changes. NNCS retains a positive count interaction, including with city random slopes, but provides no clear inflation interaction. Failed reduced NNCS fits are explicitly flagged; their nested tests are unavailable.

The primary comparisons target a within-group predictor by a higher-level moderator, with between-group associations allowed to differ. Every primary four-model comparison uses the same records and count/inflation random-effects structure. Sensitivity fits on different samples are not ranked against one another by AIC.

## CCD: rural district by state rural composition

The primary sample contains regular local districts and supervisory-union components (types 1 and 2), with positive membership and schools. The minimum of 10 eligible districts per state was reapplied. Vermont was excluded because the raw data record its ELL totals at supervisory-union centers while component districts report zero. This is a restriction on reporting comparability; no union ELL total was reassigned to a district.

The within-state predictor is rural status minus the eligible-district state rural share. The state share is common to all districts in that state and is standardized over distinct states. A quadratic context term allows a separate between-state relationship. Controls are standardized log enrollment and log schools, city locale, small district, one school, and union-component status. Log enrollment is the count offset. Both components include state random intercepts.

A one-unit within-state contrast corresponds to rural versus non-rural status at the same state composition. The reported interaction is the change in that contrast per one across-state SD of state rural composition. Exponentiating it gives the multiplier of the rural/non-rural rate ratio in the count component, or of the modeled zero-class odds ratio in the inflation component.

### Samples

| Sample | Records | Groups | Smallest group | Zero outcome % |
| --- | --- | --- | --- | --- |
| primary | 13,179 | 48 | 17 | 30.98 |
| include_vt | 13,416 | 49 | 17 | 32.20 |
| type1 | 12,949 | 47 | 17 | 30.99 |
| small | 13,179 | 48 | 17 | 30.98 |

### Primary model comparisons

| Model | AIC | Log likelihood | Numerically acceptable | Max Newton correction (SE units) |
| --- | --- | --- | --- | --- |
| Additive within-city/state association | 108738.90 | -54346.45 | True | 0.000455 |
| Within interaction in count only | 108638.53 | -54295.27 | True | 0.000358 |
| Within interaction in inflation only | 108706.95 | -54329.47 | True | 0.000852 |
| Within interaction in both components | 108618.86 | -54284.43 | True | 0.000131 |
| NB comparator with count interaction | 111963.58 | -55968.79 | True | 0.000292 |

### Within-group interactions in the joint model

| Component | Coefficient | SE | 95% CI | Wald p | Exponentiated coefficient |
| --- | --- | --- | --- | --- | --- |
| cond | 0.3331 | 0.0341 | [0.2663, 0.3999] | 1.5e-22 | 1.3953 |
| zi | -0.4106 | 0.0858 | [-0.5788, -0.2424] | 1.7e-06 | 0.6632 |

### Nested tests of within-group moderation

| Test | LR | df | p | Numerically valid comparison | Change in AIC |
| --- | --- | --- | --- | --- | --- |
| Add count interaction | 102.360 | 1 | 4.6e-24 | True | -100.36 |
| Add inflation interaction | 33.946 | 1 | 5.7e-09 | True | -31.95 |
| Add inflation given count interaction | 21.672 | 1 | 3.2e-06 | True | -19.67 |
| Add count given inflation interaction | 90.086 | 1 | 2.3e-21 | True | -88.09 |

### Planned joint-model checks

| Specification | Records | Count interaction | Inflation interaction | Numerically acceptable |
| --- | --- | --- | --- | --- |
| State random slopes in both components | 13,179 | 0.4407 (p=7.5e-07) | -0.3430 (p=0.0013) | True |
| Include Vermont | 13,416 | 0.3365 (p=1.7e-22) | -0.4343 (p=4.4e-07) | True |
| Linear between-state context | 13,179 | 0.3330 (p=1.5e-22) | -0.4083 (p=1.8e-06) | True |
| Secondary small-district interaction | 13,179 | 0.3809 (p=1.5e-11) | -0.3442 (p=0.00045) | True |
| State random count slope | 13,179 | 0.4401 (p=8.1e-07) | -0.3607 (p=3.7e-05) | True |
| Independent type-1 districts only | 12,949 | 0.3568 (p=9.4e-25) | -0.4160 (p=1.8e-06) | True |
| Additional partial union count effect | 13,179 | 0.3341 (p=1.2e-22) | -0.4107 (p=1.7e-06) | True |

The opposite signs persist across the planned institutional and reporting restrictions. Allowing a state random count slope lowers AIC by about 204 relative to the intercept-only joint model. In that specification the count interaction is 0.4401 (p=8.05e-7) and inflation interaction is -0.3607 (p=3.67e-5). Allowing slopes in both components gives 0.4407 (p=7.54e-7) and -0.3430 (p=0.00130). The additional inflation slope variance does not materially improve AIC beyond the count-slope specification. Random count slopes deserve inclusion in the reported application because they represent meaningful residual variation in the rural contrast across states.

### Example contrasts from the primary joint model

These predictions set random effects to zero; they are not averages integrating over the random-effects distribution. The contrast and reference covariate settings are recorded in the prediction tables.

| Context (SD units) | Conditional count ratio | Modeled zero-class odds ratio | Observed expected-count ratio |
| --- | --- | --- | --- |
| -1 | 0.528 | 3.238 | 0.483 |
| 0 | 0.736 | 2.148 | 0.693 |
| 1 | 1.027 | 1.425 | 0.998 |

### Random effects and numerical diagnostics

| Component | Group | Random term | SD | Near zero boundary |
| --- | --- | --- | --- | --- |
| cond | state | (Intercept) | 0.79131 | False |
| zi | state | (Intercept) | 1.10372 | False |

Every planned fit passed the recorded optimizer/Hessian/gradient criteria. Boundary variance estimates, where present, still require a parsimonious interpretation.

Complete tables: [coefficients](outputs/ccd/coefficients.csv), [model comparisons](outputs/ccd/model_comparison.csv), [random effects](outputs/ccd/random_effects.csv), [optimizer attempts](outputs/ccd/optimizer_attempts.csv), and [exact formulas](outputs/ccd/model_specifications.csv).

## NNCS: within-city disadvantage by city inequality

The primary sample retains city-specific tract/segment records, requiring complete annual homicide counts in 2010-2013 and the original tract covariates. The same three cities with fractional totals are excluded. Population times four is the count exposure; partial-tract status is a control in both components.

Disadvantage is separated into a tract deviation from its city mean and the city mean. The deviation is divided by its pooled within-city SD; city means and Gini are standardized over distinct cities. Minority concentration, instability, and vacancy remain the original standardized tract controls in the primary specification. The city-mean-disadvantage by Gini interaction is included separately in both components, so within-city and between-city moderation are not constrained to be equal. Both components include city random intercepts.

The reported interaction is the change in the association for one pooled within-city SD of tract disadvantage per one across-city SD of Gini. The metro check adds a count random intercept for METROID2 while preserving the city effects. Only nine of the 52 regional areas/divisions contain multiple sampled cities.

### Samples

| Sample | Records | Groups | Smallest group | Zero outcome % |
| --- | --- | --- | --- | --- |
| primary | 6,849 | 67 | 25 | 44.43 |
| whole | 5,838 | 67 | 4 | 40.70 |

### Primary model comparisons

| Model | AIC | Log likelihood | Numerically acceptable | Max Newton correction (SE units) |
| --- | --- | --- | --- | --- |
| Additive within-city/state association | unavailable | unavailable | False | unavailable |
| Within interaction in count only | 19480.23 | -9718.12 | True | 0.000219 |
| Within interaction in inflation only | unavailable | unavailable | False | unavailable |
| Within interaction in both components | 19481.75 | -9717.88 | True | 0.002170 |
| NB comparator with count interaction | 19528.80 | -9752.40 | True | 0.000200 |

### Within-group interactions in the joint model

| Component | Coefficient | SE | 95% CI | Wald p | Exponentiated coefficient |
| --- | --- | --- | --- | --- | --- |
| cond | 0.1087 | 0.0213 | [0.0671, 0.1504] | 3.1e-07 | 1.1149 |
| zi | 0.2254 | 0.3115 | [-0.3851, 0.8360] | 0.4693 | 1.2529 |

### Nested tests of within-group moderation

| Test | LR | df | p | Numerically valid comparison | Change in AIC |
| --- | --- | --- | --- | --- | --- |
| Add count interaction | unavailable | 1 | unavailable | False | unavailable |
| Add inflation interaction | unavailable | 1 | unavailable | False | unavailable |
| Add inflation given count interaction | 0.480 | 1 | 0.4883 | True | 1.52 |
| Add count given inflation interaction | unavailable | 1 | unavailable | False | unavailable |

### Planned joint-model checks

| Specification | Records | Count interaction | Inflation interaction | Numerically acceptable |
| --- | --- | --- | --- | --- |
| Additive between-city association | 6,849 | 0.1014 (p=1.3e-06) | 0.4147 (p=0.0929) | True |
| Decompose all tract controls | 6,849 | 0.1149 (p=4.4e-08) | 0.1671 (p=0.6112) | True |
| City random count slope | 6,849 | 0.1058 (p=0.0056) | 0.1389 (p=0.6952) | True |
| Fixed inflation; city effect in count only | 6,849 | 0.1094 (p=2.3e-07) | 0.2378 (p=0.4286) | True |
| Additional metro count intercept | 6,849 | 0.1095 (p=2.6e-07) | 0.2609 (p=0.3836) | True |
| Whole tracts only | 5,838 | 0.1112 (p=1.7e-06) | 0.1851 (p=0.5422) | True |

The within-city count interaction remains positive in the whole-tract model (0.1112, p=1.69e-6), with metro dependence (0.1095, p=2.64e-7), and when the other tract covariates are also separated into within/between terms (0.1149, p=4.36e-8). The city random count slope lowers AIC by about 40 relative to the intercept-only joint model and widens the interaction SE: 0.1058 (SE 0.0382, p=0.00561). Inflation moderation remains unsupported in each of these checks. The NNCS evidence therefore supports count-process moderation; it does not establish the dual-process opposite-sign pattern.

### Example contrasts from the primary joint model

These predictions set random effects to zero; they are not averages integrating over the random-effects distribution. The contrast and reference covariate settings are recorded in the prediction tables.

| Context (SD units) | Conditional count ratio | Modeled zero-class odds ratio | Observed expected-count ratio |
| --- | --- | --- | --- |
| -1 | 1.064 | 0.220 | 1.205 |
| 0 | 1.186 | 0.275 | 1.263 |
| 1 | 1.323 | 0.345 | 1.363 |

### Random effects and numerical diagnostics

| Component | Group | Random term | SD | Near zero boundary |
| --- | --- | --- | --- | --- |
| cond | city | (Intercept) | 0.60610 | False |
| zi | city | (Intercept) | 0.68210 | False |

Numerical limitations: primary_additive, primary_inflation. Their coefficient tests are not treated as reliable evidence. For NNCS these are models omitting the count interaction. Multiple optimizer attempts, profiled optimization, and a mapped-coefficient bounded retry did not produce an acceptable Hessian/score combination. A mapped coefficient fixed to zero represents the exact specified reduced model. The affected likelihood-ratio comparisons are unavailable; the joint-model Wald results and the valid count-only versus joint comparison remain separately reported.

Complete tables: [coefficients](outputs/nncs/coefficients.csv), [model comparisons](outputs/nncs/model_comparison.csv), [random effects](outputs/nncs/random_effects.csv), [optimizer attempts](outputs/nncs/optimizer_attempts.csv), and [exact formulas](outputs/nncs/model_specifications.csv).

## Interpretation boundaries

These are associational refits of moderators previously selected in exploratory analyses. Nominal p-values and the targeted nested comparisons do not remove that selection. The new scales, samples, and adjustment terms differ from the original fits, so raw interaction coefficients should not be compared as if their units were identical.

The count component describes the mean conditional on the count-generating class. The inflation component describes the model-based zero class, whose substantive membership is unobserved. Neither a clean hierarchy nor a statistically significant inflation coefficient establishes that an observed zero is known to be structural. Opposite coefficient signs also do not by themselves imply opposing effects on the observed expected outcome.

The final numerical criteria require optimizer code zero, a positive-definite Hessian, maximum absolute Newton correction below 0.01 parameter standard errors, and Newton decrement below 0.01. The initial raw-gradient cutoff was unnecessarily dependent on parameter and likelihood scales; raw gradients and the original attempts remain recorded. The independent curvature audit and a strict warm refinement confirmed that the completed joint fits were already extremely close to their optima. The identical specification was preserved for retries, and remaining fits reuse compatible joint-model starting values. Optimizer attempts and warnings are retained with each model object. These checks establish numerical adequacy for reported fits, rather than comprehensive validation of the statistical assumptions.

## Reproducibility

Run the saved R script with argument `ccd` or `nncs`; acceptable model checkpoints are reused and failed specifications are retried. The final mapped retries and their adoption are reproduced by `retry_nncs_mapped.R` and `adopt_mapped_candidates.R`; `finalize_outputs.R` collects all completed and failed attempts into the final result tables. Each model object, analysis dataset, sample summary, scaling definition, exact formula, optimizer attempt, and R session description is saved under `outputs`. The Python report builder reads only the new result tables.
