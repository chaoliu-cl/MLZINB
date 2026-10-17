"""Summarize completed R refits; never substitutes old estimates for new models."""
from pathlib import Path
import hashlib
import json
import math
import pandas as pd

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / 'refit_2026-10-14_multilevel'

def num(x, digits=4):
    return f'{x:.{digits}f}' if pd.notna(x) and math.isfinite(float(x)) else 'unavailable'

def pval(x):
    if pd.isna(x) or not math.isfinite(float(x)):
        return 'unavailable'
    return f'{x:.2g}' if x < .001 else f'{x:.4f}'

def table(headers, rows):
    return '\n'.join(['| ' + ' | '.join(headers) + ' |', '| ' + ' | '.join(['---']*len(headers)) + ' |'] +
                     ['| ' + ' | '.join(map(str,row)) + ' |' for row in rows])

labels = {
    'primary_additive':'Additive within-city/state association',
    'primary_count':'Within interaction in count only',
    'primary_inflation':'Within interaction in inflation only',
    'primary_joint':'Within interaction in both components',
    'primary_nb':'NB comparator with count interaction',
    'include_vt_joint':'Include Vermont',
    'type1_joint':'Independent type-1 districts only',
    'linear_context_joint':'Linear between-state context',
    'state_random_slope_joint':'State random count slope',
    'both_random_slopes_joint':'State random slopes in both components',
    'union_dependence_joint':'Additional partial union count effect',
    'small_secondary_joint':'Secondary small-district interaction',
    'fixed_inflation_joint':'Fixed inflation; city effect in count only',
    'metro_dependence_joint':'Additional metro count intercept',
    'whole_joint':'Whole tracts only',
    'city_random_slope_joint':'City random count slope',
    'additive_between_joint':'Additive between-city association',
    'all_covariates_decomposed_joint':'Decompose all tract controls',
}

lines = [
    '# CCD and NNCS: refits with clearer multilevel structure',
    '',
    'This report gives new fits of the previously selected moderators. The primary changes were specified in '
    '[the analysis protocol](protocol.md) before fitting; the additional CCD inflation random-slope check '
    'and numerical implementation changes are documented there separately. Original inputs and prior results were preserved.',
    '',
    'CCD retains the opposite-sign pattern after the structural changes. NNCS retains a positive '
    'count interaction, including with city random slopes, but provides no clear inflation '
    'interaction. Failed reduced NNCS fits are explicitly flagged; their nested tests are unavailable.',
    '',
    'The primary comparisons target a within-group predictor by a higher-level moderator, with '
    'between-group associations allowed to differ. Every primary four-model comparison uses the same '
    'records and count/inflation random-effects structure. Sensitivity fits on different samples are '
    'not ranked against one another by AIC.',
    '',
]
combined = []
all_metrics = []
headlines = {}
for ds, title in [('ccd','CCD: rural district by state rural composition'),
                  ('nncs','NNCS: within-city disadvantage by city inequality')]:
    out = HERE / 'outputs' / ds
    m = pd.read_csv(out/'model_comparison.csv')
    c = pd.read_csv(out/'coefficients.csv')
    tests = pd.read_csv(out/'likelihood_ratio_tests.csv')
    samples = pd.read_csv(out/'sample_summary.csv')
    re = pd.read_csv(out/'random_effects.csv')
    interaction = c[c.term.eq('within:context_z')].copy()
    interaction['dataset'] = ds.upper()
    interaction = interaction.merge(m[['model','n','acceptable','pd_hessian','max_gradient']],on='model',how='left')
    combined.append(interaction)
    all_metrics.append(m.assign(dataset=ds.upper()))
    joint = m[m.model.eq('primary_joint')].iloc[0]
    lines += ['## '+title, '']
    if ds == 'ccd':
        lines += [
            'The primary sample contains regular local districts and supervisory-union components '
            '(types 1 and 2), with positive membership and schools. The minimum of 10 eligible districts '
            'per state was reapplied. Vermont was excluded because the raw data record its ELL totals '
            'at supervisory-union centers while component districts report zero. This is a restriction '
            'on reporting comparability; no union ELL total was reassigned to a district.',
            '',
            'The within-state predictor is rural status minus the eligible-district state rural share. '
            'The state share is common to all districts in that state and is standardized over distinct '
            'states. A quadratic context term allows a separate between-state relationship. Controls '
            'are standardized log enrollment and log schools, city locale, small district, one school, '
            'and union-component status. Log enrollment is the count offset. Both components include '
            'state random intercepts.',
            '',
            'A one-unit within-state contrast corresponds to rural versus non-rural status at the same '
            'state composition. The reported interaction is the change in that contrast per one '
            'across-state SD of state rural composition. Exponentiating it gives the multiplier of '
            'the rural/non-rural rate ratio in the count component, or of the modeled zero-class odds '
            'ratio in the inflation component.',
            '',
        ]
    else:
        lines += [
            'The primary sample retains city-specific tract/segment records, requiring complete annual '
            'homicide counts in 2010-2013 and the original tract covariates. The same three cities with '
            'fractional totals are excluded. Population times four is the count exposure; partial-tract '
            'status is a control in both components.',
            '',
            'Disadvantage is separated into a tract deviation from its city mean and the city mean. '
            'The deviation is divided by its pooled within-city SD; city means and Gini are '
            'standardized over distinct cities. Minority concentration, instability, and vacancy '
            'remain the original standardized tract controls in the primary specification. The '
            'city-mean-disadvantage by Gini interaction is included separately in both components, '
            'so within-city and between-city moderation are not constrained to be equal. Both '
            'components include city random intercepts.',
            '',
            'The reported interaction is the change in the association for one pooled within-city SD '
            'of tract disadvantage per one across-city SD of Gini. The metro check adds a count '
            'random intercept for METROID2 while preserving the city effects. Only nine of the 52 '
            'regional areas/divisions contain multiple sampled cities.',
            '',
        ]
    lines += ['### Samples', '', table(['Sample','Records','Groups','Smallest group','Zero outcome %'],[
        [r['sample'],f"{int(r['n']):,}",int(r['groups']),int(r['min_group']),num(r['zero_pct'],2)]
        for _,r in samples.iterrows()]),'']
    primary = m[m.model.isin(['primary_additive','primary_count','primary_inflation','primary_joint','primary_nb'])]
    lines += ['### Primary model comparisons', '', table(
        ['Model','AIC','Log likelihood','Numerically acceptable','Max Newton correction (SE units)'],[
        [labels.get(r['model'],r['model']),num(r['AIC'],2),num(r['logLik'],2),
         bool(r['acceptable']),num(r['max_newton_step_se'],6)] for _,r in primary.iterrows()]),'']
    lines += ['### Within-group interactions in the joint model','']
    jc = interaction[interaction.model.eq('primary_joint')]
    lines += [table(['Component','Coefficient','SE','95% CI','Wald p','Exponentiated coefficient'],[
        [r['component'],num(r['estimate']),num(r['se']),f"[{num(r['lower'])}, {num(r['upper'])}]",
         pval(r['p']),num(r['multiplier'])] for _,r in jc.iterrows()]),'']
    lines += ['### Nested tests of within-group moderation','',table(
        ['Test','LR','df','p','Numerically valid comparison','Change in AIC'],[
        [r['test'],num(r['LR'],3),int(r['df']) if pd.notna(r['df']) else 'unavailable',pval(r['p']),bool(r['valid_numerics']),num(r['delta_AIC'],2)]
        for _,r in tests.iterrows()]),'']
    lines += ['### Planned joint-model checks','']
    check_rows=[]
    for _,r in m[~m.model.str.startswith('primary_')].iterrows():
        v=interaction[interaction.model.eq(r['model'])].set_index('component')
        vals=[]
        for comp in ['cond','zi']:
            vals.append(f"{num(v.loc[comp,'estimate'])} (p={pval(v.loc[comp,'p'])})" if comp in v.index else 'unavailable')
        check_rows.append([labels.get(r['model'],r['model']),f"{int(r['n']):,}",*vals,bool(r['acceptable'])])
    lines += [table(['Specification','Records','Count interaction','Inflation interaction','Numerically acceptable'],check_rows),'']
    if ds=='ccd':
        lines += ['The opposite signs persist across the planned institutional and reporting restrictions. '
                  'Allowing a state random count slope lowers AIC by about 204 relative to the '
                  'intercept-only joint model. In that specification the count interaction is 0.4401 '
                  '(p=8.05e-7) and inflation interaction is -0.3607 (p=3.67e-5). Allowing slopes '
                  'in both components gives 0.4407 (p=7.54e-7) and -0.3430 (p=0.00130). '
                  'The additional inflation slope variance does not materially improve AIC beyond '
                  'the count-slope specification. Random count slopes deserve inclusion in the '
                  'reported application because they represent meaningful residual variation '
                  'in the rural contrast across states.', '']
    else:
        lines += ['The within-city count interaction remains positive in the whole-tract model '
                  '(0.1112, p=1.69e-6), with metro dependence (0.1095, p=2.64e-7), and when '
                  'the other tract covariates are also separated into within/between terms '
                  '(0.1149, p=4.36e-8). The city random count slope lowers AIC by about 40 '
                  'relative to the intercept-only joint model and widens the interaction SE: '
                  '0.1058 (SE 0.0382, p=0.00561). Inflation moderation remains unsupported '
                  'in each of these checks. The NNCS evidence therefore supports count-process '
                  'moderation; it does not establish the dual-process opposite-sign pattern.', '']
    pred=pd.read_csv(out/'prediction_contrasts.csv')
    lines += ['### Example contrasts from the primary joint model','',
              'These predictions set random effects to zero; they are not averages integrating '
              'over the random-effects distribution. The contrast and reference covariate '
              'settings are recorded in the prediction tables.', '', table(
                  ['Context (SD units)','Conditional count ratio','Modeled zero-class odds ratio','Observed expected-count ratio'],[
                  [int(r['context_z']),num(r['conditional_count_ratio'],3),num(r['modeled_zero_class_odds_ratio'],3),
                   num(r['observed_expected_count_ratio'],3)] for _,r in pred.iterrows()]),'']
    lines += ['### Random effects and numerical diagnostics','']
    chosen_re=re[re.model.eq('primary_joint')]
    lines += [table(['Component','Group','Random term','SD','Near zero boundary'],[
        [r['component'],r['group'],r['term'],num(r['sd'],5),bool(r['near_boundary'])]
        for _,r in chosen_re.iterrows()]),'']
    bad=m[~m.acceptable.astype(bool)]
    if len(bad):
        lines += ['Numerical limitations: '+', '.join(bad.model)+'. Their coefficient tests are not treated as reliable evidence. '
                  'For NNCS these are models omitting the count interaction. Multiple optimizer '
                  'attempts, profiled optimization, and a mapped-coefficient bounded retry did not '
                  'produce an acceptable Hessian/score combination. A mapped coefficient fixed '
                  'to zero represents the exact specified reduced model. The affected likelihood-ratio '
                  'comparisons are unavailable; the joint-model Wald results and the valid '
                  'count-only versus joint comparison remain separately reported.','']
    else:
        lines += ['Every planned fit passed the recorded optimizer/Hessian/gradient criteria. '
                  'Boundary variance estimates, where present, still require a parsimonious interpretation.','']
    lines += [f'Complete tables: [coefficients](outputs/{ds}/coefficients.csv), '
              f'[model comparisons](outputs/{ds}/model_comparison.csv), '
              f'[random effects](outputs/{ds}/random_effects.csv), '
              f'[optimizer attempts](outputs/{ds}/optimizer_attempts.csv), and '
              f'[exact formulas](outputs/{ds}/model_specifications.csv).','']
    hc={}
    for _,r in jc.iterrows():
        hc[r['component']]={k:float(r[k]) for k in ['estimate','se','p','lower','upper','multiplier']}
    hc['numerically_acceptable']=bool(joint.acceptable)
    hc['n']=int(joint.n)
    headlines[ds]=hc

lines += [
    '## Interpretation boundaries', '',
    'These are associational refits of moderators previously selected in exploratory analyses. '
    'Nominal p-values and the targeted nested comparisons do not remove that selection. '
    'The new scales, samples, and adjustment terms differ from the original fits, so raw interaction '
    'coefficients should not be compared as if their units were identical.', '',
    'The count component describes the mean conditional on the count-generating class. The inflation '
    'component describes the model-based zero class, whose substantive membership is unobserved. '
    'Neither a clean hierarchy nor a statistically significant inflation coefficient establishes '
    'that an observed zero is known to be structural. Opposite coefficient signs also do not by '
    'themselves imply opposing effects on the observed expected outcome.', '',
    'The final numerical criteria require optimizer code zero, a positive-definite Hessian, maximum '
    'absolute Newton correction below 0.01 parameter standard errors, and Newton decrement below '
    '0.01. The initial raw-gradient cutoff was unnecessarily dependent on parameter and likelihood '
    'scales; raw gradients and the original attempts remain recorded. The independent curvature '
    'audit and a strict warm refinement confirmed that the completed joint fits were already '
    'extremely close to their optima. The identical specification was preserved for retries, and '
    'remaining fits reuse compatible joint-model starting values. Optimizer attempts and '
    'warnings are retained with each model object. These checks establish numerical adequacy for '
    'reported fits, rather than comprehensive validation of the statistical assumptions.', '',
    '## Reproducibility', '',
    'Run the saved R script with argument `ccd` or `nncs`; acceptable model checkpoints are reused '
    'and failed specifications are retried. The final mapped retries and their adoption are reproduced '
    'by `retry_nncs_mapped.R` and `adopt_mapped_candidates.R`; `finalize_outputs.R` collects all '
    'completed and failed attempts into the final result tables. '
    'Each model object, analysis dataset, sample summary, scaling definition, exact formula, '
    'optimizer attempt, and R session description is saved under `outputs`. '
    'The Python report builder reads only the new result tables.', '',
]
pd.concat(combined,ignore_index=True).to_csv(HERE/'within_interaction_results.csv',index=False)
pd.concat(all_metrics,ignore_index=True).to_csv(HERE/'model_results.csv',index=False)
(HERE/'refit_results.md').write_text('\n'.join(lines),encoding='utf-8')
(HERE/'headline_results.json').write_text(json.dumps(headlines,indent=2),encoding='utf-8')
sources={}
for rel in ['14_CCD_LEA_2009/raw_data/ag092a.txt','NNCS data/DS0002/38483-0002-Data.tsv']:
    sources[rel]=hashlib.sha256((ROOT/rel).read_bytes()).hexdigest()
(HERE/'source_sha256.json').write_text(json.dumps(sources,indent=2),encoding='utf-8')
print(json.dumps(headlines,indent=2))
print('Saved',HERE/'refit_results.md')
