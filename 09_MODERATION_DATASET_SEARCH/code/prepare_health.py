from pathlib import Path
import pandas as pd
import numpy as np
import hashlib, json, datetime
import requests

root=Path(__file__).resolve().parents[1]
base=root/'rwm'
out=base/'outputs'; out.mkdir(exist_ok=True)
d=pd.read_csv(base/'source/original_numeric.csv').rename(columns={'hhninc':'hhinc'})
d['imputed_hsat']=np.abs(d.hsat*2-np.round(d.hsat*2))>1e-6
d['imputed_educ']=np.abs(d.educ*2-np.round(d.educ*2))>1e-6
d['imputed_hand']=~d.handdum.isin([0,1])
d['source_row']=np.arange(1,len(d)+1)
# Original authors explicitly document reversed 1987 disability indicators.
fix=d.year.eq(1987)&~d.imputed_hand
d.loc[fix,'handdum']=1-d.loc[fix,'handdum']
d.to_csv(out/'all_source_annotated.csv',index=False)
flow={'source_rows':len(d),'hsat_mean_imputed':int(d.imputed_hsat.sum()),'education_mean_imputed':int(d.imputed_educ.sum()),'disability_mean_imputed':int(d.imputed_hand.sum()),'disability_1987_corrected':int(fix.sum())}
d=d.loc[~d[['imputed_hsat','imputed_educ','imputed_hand']].any(axis=1)].copy()
flow['primary_rows']=len(d)
(out/'cleaning_audit.json').write_text(json.dumps(flow,indent=2),encoding='utf-8')
d['split']=d.id.map(lambda v:'discovery' if int(hashlib.sha256(f'health-moderation-20261016:{v}'.encode()).hexdigest()[:8],16)%2==0 else 'validation')
assert not d.duplicated(['id','year']).any()
assert d.groupby('id').female.nunique().max()==1
assert d.docvis.ge(0).all() and (d.docvis%1==0).all()
assert d.hsat.between(0,10).all()
d['y']=d.docvis
d['dissatisfaction']=10-d.hsat
for source,prefix in [('dissatisfaction','x'),('working','work'),('married','marry'),('hhkids','kids'),('public','pub'),('handdum','hand'),('educ','edu')]:
    d[prefix+'_b']=d.groupby('id')[source].transform('mean')
    d[prefix+'_w']=d[source]-d[prefix+'_b']
d['log_income']=np.log1p(d.hhinc)
d['inc_b']=d.groupby('id').log_income.transform('mean')
d['inc_w']=d.log_income-d.inc_b
d['age_b']=d.groupby('id').age.transform('mean')
scales={}
# Scales depend on discovery predictors only, never on validation outcomes.
people=d.drop_duplicates('id')
for col in ['x_b','age_b','inc_b','edu_b']:
    ref=people.loc[people.split=='discovery',col]
    mean,sd=float(ref.mean()),float(ref.std())
    d[col+'z']=(d[col]-mean)/sd
    scales[col]={'mean':mean,'sd':sd}
assert d.isna().sum().sum()==0
d.to_csv(out/'analysis_data.csv',index=False)
g=d.groupby('id').agg(n=('y','size'),female=('female','first'),split=('split','first'),x_range=('dissatisfaction',lambda x:x.max()-x.min()),zero_fraction=('y',lambda x:(x==0).mean()),y_sum=('y','sum'))
g.to_csv(out/'person_support.csv')
summary=[]
for name,df in [('full',d),*list(d.groupby('split'))]:
    gg=g if name=='full' else g[g.split==name]
    summary.append(dict(sample=name,rows=len(df),people=len(gg),zero_fraction=float(df.y.eq(0).mean()),mean=float(df.y.mean()),variance=float(df.y.var()),min_n=int(gg.n.min()),max_n=int(gg.n.max()),singleton_people=int(gg.n.eq(1).sum()),varying_health_people=int(gg.x_range.gt(0).sum()),all_zero_people=int(gg.y_sum.eq(0).sum())))
pd.DataFrame(summary).to_csv(out/'sample_audit.csv',index=False)
(out/'scales.json').write_text(json.dumps(scales,indent=2),encoding='utf-8')
manifest=json.loads((root/'download_manifest.json').read_text(encoding='utf-8'))
path=base/'source/Health.rda'
if not any(x['file']==str(path.relative_to(root)) for x in manifest):
    manifest.append(dict(candidate='rwm',file=str(path.relative_to(root)),url='https://raw.githubusercontent.com/cran/Rchoice/master/data/Health.rda',sha256=hashlib.sha256(path.read_bytes()).hexdigest(),bytes=path.stat().st_size,downloaded_utc=datetime.datetime.now(datetime.timezone.utc).isoformat()))
(root/'download_manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print(pd.DataFrame(summary).to_string(index=False))
