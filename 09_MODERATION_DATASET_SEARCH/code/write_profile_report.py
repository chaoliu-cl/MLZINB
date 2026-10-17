from pathlib import Path
import sys,base64,datetime,json,re,html
import numpy as np,pandas as pd
sys.path.insert(0,str(Path(__file__).resolve().parent/'vendor'))
import markdown

root=Path(__file__).resolve().parents[1];selected=root/'bikeshare_profile';out=selected/'outputs'
def read(name):return pd.read_csv(out/name)
def fmt(v):
    if isinstance(v,(float,np.floating)):
        if np.isnan(v):return 'NA'
        if v==0:return '0'
        return f'{v:.2e}' if abs(v)<.001 else f'{v:.3f}'
    return str(v).replace('|',' / ')
def table(d):
    return '| '+' | '.join(map(str,d.columns))+' |\n| '+' | '.join(['---']*len(d.columns))+' |\n'+'\n'.join('| '+' | '.join('<1e-300' if col=='p' and isinstance(v,(float,np.floating)) and v==0 else fmt(v) for col,v in zip(d.columns,row))+' |' for row in d.itertuples(index=False,name=None))
def image(name,alt):return f'![{alt}](bikeshare_profile/figures/{name}.png)'
def diagnostic_table(d):
    d=d.copy();d['p']=d.p.astype(object)
    d.loc[d.test.isin(['dispersion','zero_inflation'])&d.p.eq(0),'p']='<.004 (500 simulations)'
    return table(d[['test','statistic','p']])
required=['full_bundle.rds','component_predictions.csv','sensitivity_audit.csv','sensitivity_tests.csv','exact_deletion_audit.csv','diagnostics/primary/tests.csv','diagnostics/primary/calibration.csv']
for name in required:assert (out/name).exists(),name
d=read('analysis_data.csv')
sample=d.groupby('sample').agg(observations=('y','size'),days=('group','nunique'),zeros=('y',lambda x:x.eq(0).sum()),mean=('y','mean'),variance=('y','var')).reset_index()
mainfits=pd.concat([read(s+'_fit_audit.csv') for s in ['discovery','validation','full']],ignore_index=True)
lrt=pd.concat([read(s+'_interaction_tests.csv') for s in ['discovery','validation','full']],ignore_index=True)
hac=pd.concat([read(s+'_HAC_joint_tests.csv') for s in ['discovery','validation','full']],ignore_index=True)
hac14=hac[hac.lag.eq(14)]
lrprimary=lrt[lrt.comparison.eq('additive -> joint')]
fullfits=mainfits[mainfits['sample'].eq('full')]
sens=read('sensitivity_audit.csv');st=read('sensitivity_tests.csv');ct=read('sensitivity_component_tests.csv')
deletions=read('exact_deletion_audit.csv')
influence_summary=json.loads((out/'deletion_approximation_summary.json').read_text())
diag=read('diagnostics/primary/tests.csv');ppc=read('diagnostics/primary/predictive_checks.csv')
pred=read('component_predictions.csv')
key=pred[pred.hour.isin([3,8,13,18,22])&pred.metric.isin(['expected','total_zero'])][['hour','context','metric','value','lower','upper']].copy()
key['context']=key.context.map({0:'Nonworking',1:'Working'})
responses=read('response_scale_moderation.csv')
score_audits=[json.loads((out/(s+'_score_verification.json')).read_text()) for s in ['discovery','validation','full']]
max_ll=max(abs(a['logLik_reconstruction_error']) for a in score_audits)
max_score=max(abs(a['score_sum_max_error']) for a in score_audits)
bf=sens[sens.model.eq('BFGS')].iloc[0]
primary_joint=fullfits[fullfits.model.eq('joint')].iloc[0]
bf_difference=float(bf.logLik-primary_joint.logLik)
pd_valid=sens.pdHess.astype(str).str.lower().eq('true')&sens.convergence.eq(0)
valid_sens=sens[pd_valid].model
inflation_sens=ct[ct.component.eq('inflation')&ct.model.isin(valid_sens)]
count_sens=ct[ct.component.eq('count')&ct.model.isin(valid_sens)]
random_diag=''
if (out/'diagnostics/random_slope/tests.csv').exists():
    random_diag='\n\nThe independent random-slope model was also checked with 500 unconditional simulations:\n\n'+diagnostic_table(read('diagnostics/random_slope/tests.csv'))+'\n\n'+image('calibration_random_slope','Random-slope model calibration')
extra_diag=''
for kind,title in [('flexible_hour_joint','Full hour-factor count model'),('varying_dispersion','Clock-time and context-varying dispersion')]:
    if (out/f'diagnostics/{kind}/tests.csv').exists():
        extra_diag+='\n\n**'+title+'**\n\n'+diagnostic_table(read(f'diagnostics/{kind}/tests.csv'))+'\n\n'+table(read(f'diagnostics/{kind}/predictive_checks.csv'))+'\n\n'+image('calibration_'+kind,title+' calibration')

text=f'''# Social-science walkthrough: contextual moderation in ML-ZINB

**Capital Bikeshare provides a supported example of contextual moderation:** the within-day clock-time profile of casual rental counts differs between working and nonworking days. The frozen revised model supports this in **2011 discovery** and **2012 temporal validation**, including calendar-time robust uncertainty. Distributional fit remains imperfect, especially in the upper tail. These are associations in one transport system, not causal effects or independent-city replication.

UCI explicitly classifies this dataset as **Social Science**. The primary sample contains **{len(d):,} recorded hours within {d.group.nunique():,} complete calendar days**, each with exactly 24 observations. **{d.y.eq(0).sum():,} counts are zero ({d.y.eq(0).mean():.2%})**. The selected example follows a transparent search and a discovery-only model revision; all previous attempts remain available.

## 1. Dataset, hierarchy and question

**Question:** Does working-day context modify the daily time pattern of casual bike rentals?

The outcome is the released hourly count of casual-user rentals. These are rental events, not unique individuals. Level 1 is a recorded clock-hour slot; level 2 is the calendar day. Workingday is a day-level indicator defined by the source as neither weekend nor holiday. It is constant within each day and varies across days. Clock-time predictors vary within every primary day.

{table(sample)}

Discovery has 305 complete days (100 nonworking and 205 working); validation has 350 (112 nonworking and 238 working). The raw download contains 17,379 hourly records across 731 days. It has 165 fewer records than a nominal 24-hours-per-day grid. The 76 incomplete days are retained in an all-records sensitivity; absent hours are not silently turned into zeros. Hourly sums reconcile exactly to the companion daily file for casual, registered and total rentals.

{image('structure_and_observed_patterns','Grouping support and observed daily profiles')}

The first two sine/cosine harmonics represent the count-component time profile; the first harmonic represents inflation. These functions have exactly zero mean within a complete 24-record day, giving a clean within-day predictor. A separate between-day mean is mathematically constant and cannot be estimated. This is a **day-level context**, not a neighborhood or institutional context. It is suitable when the paper allows repeated occasions within contextual units.

## 2. Search record and validation boundary

| Attempt | Primary finding | Decision |
| --- | --- | --- |
| German health-care panel: within-person dissatisfaction × recorded sex | Joint LR p = .07066 in discovery | Rejected as the requested supported example; its validation people were not modeled |
| Bikeshare: midday-window × workingday | Strong count evidence, but inflation interaction SE approximately 10,000 | Rejected as a regular four-model demonstration; original fits retained |
| Bikeshare: smooth daily profile × workingday, complete-day sample | Supported in discovery and temporal validation | Selected, with component and adequacy qualifications below |

The shorter COUNT::rwm extract omitted person identifiers. The full health archive was obtained and its original authors' corrections were applied before the discovery fits: 1987 disability coding was reversed, and known mean-imputed health/education/disability rows were excluded. This failed candidate is retained rather than hidden. A county-murder panel was downloaded and documented but no moderation model was fitted. Other documentation-only candidates are listed in the search protocol.

The midday analysis was revised because its inflation product concerned a region where modeled extra zeros were essentially absent. The first 2012 additive fit had been started and was stopped; **no 2012 interaction result was inspected before the daily-profile amendment**. Source-level descriptive cell summaries, including 2012 counts, had been inspected during the data audit. The final daily-profile equations and sample rule were frozen before fitting its 2012 interaction models. This is exploratory model development with a temporal check, not a preregistered study.

A simple three-attempt Bonferroni threshold is .0167; the selected primary and calendar-HAC joint tests remain far below it. This transparency calculation does not account for every possible analytic choice; the temporal validation provides the more useful check. The complete [revised protocol](bikeshare_profile/protocol.md) and [initial search protocol](search_protocol.md) are retained.

## 3. Four matched ML-ZINBs and numerical checks

All four NB2 models use identical observations and controls within each sample. The count equation includes a day random intercept, the four clock-time basis terms, workingday, month indicators, temperature and its square, humidity, wind speed and bad weather. The smaller inflation equation includes two clock-time terms, workingday, temperature, humidity and bad weather. Weather codes 3/4 are pooled because code 4 has only three source records. Released normalized weather units are retained because archived descriptions disagree about temperature transformations. Full-sample equations also include a 2012 indicator; separate-year equations cannot estimate it.

| Model | Count contextual products | Inflation contextual products |
| --- | --- | --- |
| Additive | None | None |
| Count only | 4 clock-time × workingday products | None |
| Inflation only | None | 2 clock-time × workingday products |
| Joint | 4 products | 2 products |

The primary additive-to-joint test has **6 df**, count additions have **4 df**, and inflation additions have **2 df**. This vector-predictor example should not be described as a scalar two-df joint test. No arbitrary inflation coefficient was fixed. The raw estimates, SEs, gradients and Hessian flags are saved for every fit. Inflation coefficients can be large because the transition to nighttime zeros is sharp; their joint functions and uncertainty are more meaningful than an isolated harmonic coefficient.

{table(fullfits[['model','logLik','AIC','df','convergence','pdHess','max_abs_gradient']])}

The same-count-specification NB2 comparator has AIC **{float(fullfits.loc[fullfits.model.eq('nb'),'AIC'].iloc[0]):.2f}**, versus **{primary_joint.AIC:.2f}** for the joint ML-ZINB. This supports a useful mixture in this working specification. It does not verify a genuine structural non-rental class. No ordinary chi-square NB-versus-ZINB boundary test is claimed. The alternate BFGS joint fit changes log likelihood by **{bf_difference:.6g}**; its full numerical audit is retained.

## 4. Moderation evidence and component location

{table(lrprimary[['sample','LR','df','p']])}

The conditional additions, which hold the other component's contextual products present, give:

{table(lrt[lrt.comparison.isin(['count -> joint','inflation -> joint'])][['sample','comparison','LR','df','p']])}

Because hours within a day are dependent and adjacent days may also be dependent, the workflow reconstructs **day marginal-likelihood scores including fixed effects, dispersion and random-intercept SD**. Their likelihood sum matches glmmTMB within {max_ll:.2e}; summed scores match the package gradient within {max_score:.2e}. Sandwich covariance uses G/(G−1). Calendar-HAC additionally uses 14-day Bartlett lags; excluded dates retain their calendar positions. These checks make the group-aware uncertainty independently reviewable.

{table(hac14[['sample','component','Wald','df','p']])}

The 2012 validation retains a highly supported count-profile interaction and a supported inflation-profile interaction under the frozen primary equation. Lag-7 and lag-28 results are also retained. The claim concerns entire clock-time profiles; individual sine/cosine coefficients are basis parameters, not standalone morning or evening effects.

## 5. Component-aware visual walkthrough

For each reference record, compute the count-process mean μ, modeled structural-zero probability π, overall expectation (1−π)μ, and total zero probability π+(1−π)[φ/(φ+μ)]^φ. Average each record-level quantity only after forming the mixture. μ is not the observed mean among positive rentals.

Both day types are standardized over the same equal-day empirical distribution of calendar and weather covariates. Day random effects are fixed at zero. Thus these are common-reference model associations, not predictions integrated over the random-effect distribution or causal counterfactuals. Clock hour and all of its basis functions are updated together. Bands are pointwise 95% calendar-HAC intervals, conditional on the observed reference covariates.

{image('component_predictions','Count, inflation, observable expectation and total-zero profiles')}

{table(key)}

The profiles distinguish a change in the intensity of the count process from a change in the modeled extra-zero process. Total zeros also include negative-binomial zeros. A latent π curve must not be read as a measured proportion of people who never cycle.

{image('context_contrasts','Context contrasts with additive-model overlays')}

The additive model also produces clock-dependent differences on the response scale because its links are nonlinear. Here, the joint product tests independently establish link-scale moderation. The plots then show its magnitude and how the components combine. A descriptive summary comparing the average of hours 10–15 with the average of the other 18 hours is saved below; this window summary is not the primary harmonic-product test.

{table(responses)}

## 6. Model adequacy

Each diagnostic uses 500 unconditional simulations with fresh day effects and fixed fitted parameters. Individual residual tests are sensitive to small discrepancies with 15,720 records. Assess the magnitude and hour/day-type pattern alongside p-values.

{diagnostic_table(diag)}

{table(ppc)}

{image('calibration_primary','Observed counts, zeros and positive counts against simulation envelopes')}

{image('residual_patterns_primary','Residual hour patterns and calendar-day dependence')}
{random_diag}
{extra_diag}

The primary model simulates a median maximum of about 907 rentals against the observed 367, with a lower 95% envelope around 694. This is a material upper-tail discrepancy. Flexible hour effects improve it, and time/context-varying dispersion calibrates the zero fraction much better (zero test p=.884), but neither removes the upper-tail issue. The dispersion sensitivity was added in response to this diagnostic failure, as documented in [the adequacy amendment](bikeshare_profile/adequacy_amendment.md). Its estimates are secondary, not a newly independent validation result.

Remaining discrepancies constrain claims about distributional adequacy and latent components. A supported and repeatedly observed clock-time interaction does not certify every part of the ZINB mechanism. The zero probabilities and extreme-count predictions should not be presented as fully validated probabilities. Monte Carlo diagnostic p-values reported as zero are shown at the simulation resolution rather than as impossibly precise analytic p-values.

## 7. Robustness and influential days

The variants address within-day heterogeneity, the inflation random structure, flexible clock-time shapes, weather-by-context differences, incomplete-day coverage, and optimization. Each test includes all contextual clock-time products of that model. The full hour-factor model tests 23 count products plus 2 inflation products; changing test dimensions are shown rather than comparing one selected harmonic.

{table(sens[['model','rows','AIC','convergence','pdHess','gradient','max_coef','max_se']].merge(st[['model','df','p']],on='model',how='left'))}

AIC is comparable only for models fitted to the same observations. The all-released-days variant has 17,379 rows and its AIC must not be compared directly with complete-day AIC values. These sensitivity tests use model-based covariance; the independently verified day-cluster/calendar-HAC inference belongs to the primary model.

{image('sensitivity_tests','Contextual profile tests across model variants')}

The component tests for valid variants are:

{table(ct[ct.model.isin(valid_sens)][['model','component','df','p']])}

Do not treat a significant joint test as proof that both components are robust in every specification. Inflation conclusions deserve particular attention when its equation or random structure changes. The corresponding raw model summaries and audit record all numerical flags, including any very large SEs.

The extra inflation random intercept has SD about 0.000032 and a non-positive-definite Hessian; its Wald p-value is not interpretable and is excluded from inference. The hour-factor additive comparator also has a weak inflation nuisance direction (maximum SE about 567). Its conventional LR reference is therefore not used as confirmation. The hour-factor joint model has much smaller finite SEs and provides a useful separate Wald sensitivity for the full contextual time profile.

First-order deletion influence was evaluated for all 655 days. The five largest approximate influences and five fixed evenly spaced dates were then reoptimized exactly ({len(deletions)} distinct deletions). This is not a claim of 655 exact deletion refits. The verified day sandwich and calendar-HAC provide the group-aware uncertainty; no full refit cluster bootstrap is claimed for this application.

The largest selected exact shift is {influence_summary['maximum_absolute_exact_shift_in_model_SE']:.3f} model SEs. Across the 60 selected coefficient shifts, the maximum approximation error is {influence_summary['maximum_absolute_approximation_error_in_model_SE']:.3f} model SEs and the correlation of standardized approximate/exact shifts is {influence_summary['correlation_of_standardized_shifts']:.3f}. No selected deletion removes the joint moderation evidence.

{table(deletions[['date','selection','convergence','pdHess','max_shift_model_SE','df','p']])}

{image('influential_days','Largest first-order day deletion influences')}

## 8. Recommendation for the methodological study

Use this as a **positive social-science walkthrough of contextual moderation in within-day activity profiles**, with the temporal validation and model-development history visible. It has a clean, balanced observed hierarchy, a genuine day-level moderator, an appropriate count response with observed zeros, and a supported interaction that can be assessed separately in the two mixture components.

The practical sequence is: audit grouping and coverage; freeze a substantive question; fit the four matched models; inspect component identification; test the contextual products jointly and conditionally; draw all four model quantities and an additive overlay; check adequacy; then assess group/time-aware uncertainty, richer random structures and influence. This example also shows why a numerically converged but unidentified inflation product should prompt model revision before validation.

A defensible conclusion is: **“The clock-time profile of casual bike rentals differs between working and nonworking days. This contextual association is reproduced in a subsequent year and persists under dependence-aware uncertainty. Component-aware analysis distinguishes the count-profile change from the modeled extra-zero change; conclusions about the latter remain conditional on the inflation specification and adequacy checks.”**

It does not demonstrate causal moderation, a verified structural-zero mechanism, or generalization to other cities. If the paper requires geographic contexts such as neighborhoods or schools, day-level context must be explicitly justified rather than silently substituted.

## 9. Sources, license and reproducibility

Source: [UCI Bike Sharing](https://archive.ics.uci.edu/dataset/275/bike+sharing+dataset), dataset DOI [10.24432/C5W894](https://doi.org/10.24432/C5W894), categorized by UCI as Social Science. Cite Fanaee-T and Gama (2013), *Event labeling combining ensemble detectors and background knowledge*, DOI [10.1007/s13748-013-0040-3](https://doi.org/10.1007/s13748-013-0040-3). UCI states a [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) license; its page and original archive are retained. The source is Capital Bikeshare's 2011–2012 operational data, augmented with calendar/weather information.

The original health archive and author corrections are at [the Journal of Applied Econometrics data archive](http://qed.econ.queensu.ca/jae/2003-v18.4/riphahn-wambach-million/). Its use is restricted to scientific studies. No external messages or submissions were sent. Download timestamps, URLs and SHA-256 hashes are retained in [the manifest](download_manifest.json).

Limitations include one system, observational day types, changing system size and seasonality, unavailable inventory/rider exposure, missing clock-hour records, possible daylight-saving aggregation effects, temporal dependence beyond the chosen HAC lags, and mixture-model assumptions. The primary complete-day sample changes the population of days; the all-released-days sensitivity is therefore material.

See [README](README.md) for code, software versions, reproduction and artifact locations. Final integrity verification checks data, source hashes, matched tests, score reconstruction, predictions and files; it is not a claim of statistical model perfection.

Generated {datetime.datetime.now(datetime.timezone.utc):%Y-%m-%d %H:%M UTC}.
'''
(root/'walkthrough_report.md').write_text(text,encoding='utf-8')
rendered=markdown.markdown(text,extensions=['markdown.extensions.tables','markdown.extensions.fenced_code'])
def embed(m):
    p=root/m.group(1)
    if not p.exists():raise FileNotFoundError(p)
    return 'src="data:image/png;base64,'+base64.b64encode(p.read_bytes()).decode()+'"'
rendered=re.sub(r'src="([^"]+\.png)"',embed,rendered)
css='body{font:16px/1.55 system-ui,sans-serif;color:#253345;max-width:1150px;margin:40px auto;padding:0 28px}h1{font-size:30px;line-height:1.2}h2{margin-top:2em;color:#15546b}table{border-collapse:collapse;width:100%;font-size:13px;display:block;overflow:auto}th,td{padding:8px 10px;border-bottom:1px solid #dbe2e8;text-align:left}th{background:#eef4f7}img{max-width:100%;height:auto}a{color:#176f92}code{background:#f1f4f6;padding:2px 4px}strong{color:#172b3a}'
(root/'walkthrough_report.html').write_text('<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Contextual moderation: Capital Bikeshare ML-ZINB walkthrough</title><style>'+css+'</style><body>'+rendered+'</body></html>',encoding='utf-8')
print('Created',root/'walkthrough_report.html')
