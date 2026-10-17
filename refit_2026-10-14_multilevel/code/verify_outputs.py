from pathlib import Path
import json
import numpy as np
import pandas as pd

HERE=Path(__file__).resolve().parents[1]
checks={}
for ds,expected,acceptable in [('ccd',12,12),('nncs',11,9)]:
    p=HERE/'outputs'/ds
    m=pd.read_csv(p/'model_comparison.csv')
    c=pd.read_csv(p/'coefficients.csv')
    s=pd.read_csv(p/'sample_summary.csv')
    l=pd.read_csv(p/'likelihood_ratio_tests.csv')
    assert len(m)==expected and m.model.is_unique
    assert int(m.acceptable.sum())==acceptable
    good=m[m.acceptable]
    assert np.allclose(good.AIC,2*good.df-2*good.logLik,atol=1e-5)
    assert good.pd_hessian.all() and (good.convergence==0).all()
    assert (good.max_newton_step_se<.01).all() and (good.newton_decrement<.01).all()
    assert not c.duplicated(['model','component','term']).any()
    for _,r in s.iterrows():
        dat=pd.read_csv(p/f"sample_{r['sample']}.csv")
        assert len(dat)==r['n']
        key='LEAID' if ds=='ccd' else 'tract_city_id'
        assert dat[key].is_unique
        group='state' if ds=='ccd' else 'CITY_ID'
        assert dat[group].nunique()==r['groups']
        assert (dat.groupby(group).context_z.nunique()==1).all()
        assert (m.loc[m['sample']==r['sample'],'n']==r['n']).all()
    for _,r in l[l.valid_numerics].iterrows():
        a=m[m.model==r.reduced].iloc[0];b=m[m.model==r.full].iloc[0]
        assert a.acceptable and b.acceptable and a['n']==b['n']
        assert np.isclose(r.LR,2*(b.logLik-a.logLik),atol=1e-6)
        assert np.isclose(r.delta_AIC,b.AIC-a.AIC,atol=1e-6)
    jc=c[(c.model=='primary_joint')&(c.term=='within:context_z')]
    assert set(jc.component)=={'cond','zi'}
    checks[ds]={'models':len(m),'numerically_acceptable':int(m.acceptable.sum()),
                'primary_records':int(m.loc[m.model=='primary_joint','n'].iloc[0]),
                'valid_likelihood_ratio_comparisons':int(l.valid_numerics.sum())}
report=(HERE/'refit_results.md').read_text(encoding='utf-8')
assert 'unavailable' in report and '0.00561' in report and 'Vermont' in report
(HERE/'verification_summary.json').write_text(json.dumps(checks,indent=2),encoding='utf-8')
print(json.dumps(checks,indent=2))
