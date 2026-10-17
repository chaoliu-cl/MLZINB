from pathlib import Path
import datetime,json,hashlib,ast,re,subprocess,sys
import numpy as np,pandas as pd
from scipy.special import expit
from scipy.stats import chi2
from bs4 import BeautifulSoup

root=Path(__file__).resolve().parents[1];selected=root/'bikeshare_profile';out=selected/'outputs'
checks={};details={}
def check(name,condition):
    checks[name]=bool(condition)
    if not condition:raise AssertionError(name)
manifest=json.loads((root/'download_manifest.json').read_text())
check('download_hashes',all(hashlib.sha256((root/x['file']).read_bytes()).hexdigest()==x['sha256'] for x in manifest))
d=pd.read_csv(out/'analysis_data.csv');raw=pd.read_csv(root/'bikeshare/source/hour.csv')
check('sample_and_day_structure',len(d)==15720 and d.group.nunique()==655 and d.groupby('group').size().eq(24).all() and d.groupby('group').context.nunique().eq(1).all())
check('unique_keys',not d.duplicated(['dteday','hr']).any())
check('complete_variables',d.notna().all().all())
check('count_measurement',d.y.ge(0).all() and (d.y%1==0).all())
joined=d.merge(raw[['instant','casual','hr','workingday']],on='instant',suffixes=('','_raw'),validate='one_to_one')
check('source_values',len(joined)==len(d) and joined.y.eq(joined.casual_raw).all() and joined.hr.eq(joined.hr_raw).all() and joined.context.eq(joined.workingday_raw).all())
check('within_day_harmonic_means',all(d.groupby('group')[c].mean().abs().max()<1e-12 for c in ['sin1','cos1','sin2','cos2']))
check('temporal_split',set(d.loc[d['sample'].eq('discovery'),'group']).isdisjoint(d.loc[d['sample'].eq('validation'),'group']) and d.groupby('sample').yr.nunique().eq(1).all())
for s in ['discovery','validation','full']:
    a=pd.read_csv(out/f'{s}_fit_audit.csv');tests=pd.read_csv(out/f'{s}_interaction_tests.csv');a=a.set_index('model')
    check(s+'_main_numerics',a.convergence.eq(0).all() and a.pdHess.astype(str).str.lower().eq('true').all() and np.isfinite(a.logLik).all())
    check(s+'_matched_sample',a.rows.nunique()==1 and a.groups.nunique()==1)
    for row in tests.itertuples():
        lo,hi=row.comparison.split(' -> ');lr=2*(a.loc[hi,'logLik']-a.loc[lo,'logLik']);df=int(a.loc[hi,'df']-a.loc[lo,'df'])
        check(s+'_'+row.comparison,np.isclose(lr,row.LR,atol=1e-7) and df==row.df and np.isclose(chi2.sf(lr,df),row.p,atol=1e-14))
    audit=json.loads((out/f'{s}_score_verification.json').read_text())
    check(s+'_group_likelihood_scores',abs(audit['logLik_reconstruction_error'])<1e-5 and audit['score_sum_max_error']<.002)
    hc=pd.read_csv(out/f'{s}_HAC_joint_tests.csv')
    check(s+'_HAC_grid',len(hc)==9 and set(hc.lag)=={7,14,28} and set(hc.component)=={'joint','count','inflation'})
    co=pd.read_csv(out/f'{s}_coefficients.csv')
    check(s+'_finite_coefficient_uncertainty',np.isfinite(co[['estimate','se']]).all().all() and co.se.gt(0).all())
    details[s+'_max_coefficient_SE']=float(co.se.max())
    details[s+'_joint_LR_p']=float(tests.iloc[0].p)
    details[s+'_HAC14_joint_p']=float(hc.loc[hc.lag.eq(14)&hc.component.eq('joint'),'p'].iloc[0])
pred=pd.read_csv(out/'component_predictions.csv')
check('prediction_grid',len(pred)==192 and not pred.duplicated(['hour','context','metric']).any())
check('prediction_interval_order',(pred.lower<=pred.value).all() and (pred.upper>=pred.value).all())
prob=pred[pred.metric.isin(['pi','total_zero'])]
check('probability_bounds',prob[['value','lower','upper']].ge(0).all().all() and prob[['value','lower','upper']].le(1).all().all())
check('R_prediction_gradient_checks','PASS' in (out/'prediction_verification.txt').read_text())
# Independent Python reconstruction of all standardized predictions from R design matrices.
folder=out/'score_inputs/full';X=pd.read_csv(folder/'X.csv');Z=pd.read_csv(folder/'Z.csv');par=pd.read_csv(folder/'parameters.csv').value.to_numpy();p=X.shape[1];q=Z.shape[1];phi=np.exp(par[-2]);maxerr=0;mixture_difference=0
for hour in range(24):
    for ctx in [0,1]:
        x=X.copy();z=Z.copy()
        for mat in [x,z]:
            if 'context' in mat:mat['context']=ctx
            for k in [1,2]:
                for label,v in [(f'sin{k}',np.sin(2*np.pi*k*hour/24)),(f'cos{k}',np.cos(2*np.pi*k*hour/24))]:
                    if label in mat:mat[label]=v
                    for term in [label+':context','context:'+label]:
                        if term in mat:mat[term]=v*ctx
        mu=np.exp(x.to_numpy()@par[:p]);pi=expit(z.to_numpy()@par[p:p+q]);nb0=np.exp(-phi*np.log1p(mu/phi))
        val=dict(mu=float(mu.mean()),pi=float(pi.mean()),expected=float(((1-pi)*mu).mean()),total_zero=float((pi+(1-pi)*nb0).mean()))
        mixture_difference=max(mixture_difference,abs(val['expected']-(1-val['pi'])*val['mu']))
        for metric,v in val.items():maxerr=max(maxerr,abs(v-float(pred.loc[pred.hour.eq(hour)&pred.context.eq(ctx)&pred.metric.eq(metric),'value'].iloc[0])))
check('independent_Python_prediction_values',maxerr<1e-7)
details['maximum_prediction_reconstruction_error']=maxerr;details['maximum_mean_mixture_vs_product_of_means_difference']=mixture_difference
influence=pd.read_csv(out/'full_influence_approximation.csv');deletion=pd.read_csv(out/'exact_deletion_audit.csv')
fixed=np.array(sorted(d.dteday.unique()))[np.unique(np.round(np.linspace(1,655,5)).astype(int)-1)]
expected=set(influence.id.head(5))|set(fixed)
check('influence_coverage',len(influence)==655 and influence.id.nunique()==655)
check('exact_deletion_coverage',set(deletion.date)==expected)
check('exact_deletion_numerics',deletion.convergence.eq(0).all() and deletion.pdHess.astype(str).str.lower().eq('true').all())
sens=pd.read_csv(out/'sensitivity_audit.csv')
check('sensitivity_coverage',set(sens.model)=={'random_slope','inflation_intercept','third_count_harmonic','second_inflation_harmonic','temperature_context','flexible_hour_additive','flexible_hour_joint','BFGS','all_released_days','varying_dispersion'})
details['sensitivity_numerical_flags']=sens.loc[~(sens.convergence.eq(0)&sens.pdHess.astype(str).str.lower().eq('true')),['model','convergence','pdHess','warnings']].fillna('').to_dict('records')
for kind in ['primary','random_slope','flexible_hour_joint','varying_dispersion']:
    check(kind+'_diagnostic_outputs',all((out/'diagnostics'/kind/name).exists() for name in ['DHARMa.rds','tests.csv','predictive_checks.csv','calibration.csv','residuals.csv']))
report=BeautifulSoup((root/'walkthrough_report.html').read_text(encoding='utf-8'),'html.parser')
check('embedded_report_figures',all(im.get('src','').startswith('data:image/png;base64,') for im in report.find_all('img')))
missing=[]
for a in report.find_all('a',href=True):
    href=a['href']
    if not re.match(r'^(https?:|mailto:|#)',href) and not (root/href.split('#')[0]).exists():missing.append(href)
check('report_links',not missing)
check('no_report_placeholders',not re.search(r'\b(TODO|TBD|PLACEHOLDER)\b',report.get_text()))
for code in (root/'code').glob('*.py'):ast.parse(code.read_text(encoding='utf-8'))
check('Python_syntax',True)
record=dict(verified_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),all_passed=all(checks.values()),scope='Provenance, reproducibility, numerical identities and artifact integrity; not proof of statistical adequacy or causality.',checks=checks,details=details)
dest=root/'outputs';dest.mkdir(exist_ok=True);(dest/'bundle_verification.json').write_text(json.dumps(record,indent=2),encoding='utf-8')
print(json.dumps(record,indent=2))
