from pathlib import Path
import pandas as pd,numpy as np,json
root=Path(__file__).resolve().parents[1]/'bikeshare';out=root/'outputs';out.mkdir(exist_ok=True)
d=pd.read_csv(root/'source/hour.csv');day=pd.read_csv(root/'source/day.csv')
assert not d.duplicated(['dteday','hr']).any() and d.notna().all().all()
assert (d.casual+d.registered==d.cnt).all()
assert d.casual.ge(0).all() and (d.casual%1==0).all()
assert d.groupby('dteday').workingday.nunique().max()==1
assert (d.workingday==((~d.weekday.isin([0,6]))&d.holiday.eq(0)).astype(int)).all()
sums=d.groupby('dteday')[['casual','registered','cnt']].sum().reset_index().merge(day,on='dteday',suffixes=('_hour','_day'))
for col in ['casual','registered','cnt']:assert (sums[col+'_hour']==sums[col+'_day']).all()
d['y']=d.casual;d['midday']=d.hr.between(10,15).astype(int)
d['x_b']=d.groupby('dteday').midday.transform('mean');d['x_w']=d.midday-d.x_b;d['x_b0']=d.x_b-.25
d['context']=d.workingday
d['group']=pd.factorize(d.dteday,sort=True)[0]+1
d['badweather']=d.weathersit.ge(3).astype(int)
for k in [1,2,3]:
    d[f'sin{k}']=np.sin(2*np.pi*k*d.hr/24)
    d[f'cos{k}']=np.cos(2*np.pi*k*d.hr/24)
d['sample']=np.where(d.yr.eq(0),'discovery','validation')
d['complete_day']=d.groupby('dteday').hr.transform('size').eq(24)
dates=pd.to_datetime(d.dteday);d['week']=((dates-dates.min()).dt.days//7).astype(int)
d.to_csv(out/'analysis_data.csv',index=False)
g=d.groupby('dteday').agg(context=('context','first'),n=('y','size'),midday_n=('midday','sum'),mean=('y','mean'),zero_fraction=('y',lambda x:x.eq(0).mean()),total=('y','sum'),sample=('sample','first'))
g.to_csv(out/'day_support.csv')
summary=[]
for name,df in [('full',d),*list(d.groupby('sample'))]:
    gg=g if name=='full' else g[g['sample']==name]
    summary.append(dict(sample=name,rows=len(df),days=len(gg),zero_fraction=float(df.y.eq(0).mean()),mean=float(df.y.mean()),variance=float(df.y.var()),minimum_records=int(gg.n.min()),complete_days=int(gg.n.eq(24).sum()),working_days=int(gg.context.eq(1).sum()),nonworking_days=int(gg.context.eq(0).sum()),days_with_both_windows=int((gg.midday_n.gt(0)&gg.midday_n.lt(gg.n)).sum())))
pd.DataFrame(summary).to_csv(out/'sample_audit.csv',index=False)
cells=d.groupby(['sample','context','hr']).agg(n=('y','size'),zeros=('y',lambda x:x.eq(0).sum()),mean=('y','mean')).reset_index()
cells.to_csv(out/'hour_support.csv',index=False)
audit=dict(source_rows=len(d),daily_rows=len(day),possible_nominal_24_hour_rows=len(day)*24,absent_nominal_hours=len(day)*24-len(d),duplicate_keys=0,missing_values=0,daily_count_reconciliation=True,minimum_count=int(d.y.min()),maximum_count=int(d.y.max()))
(out/'data_verification.json').write_text(json.dumps(audit,indent=2))
print(pd.DataFrame(summary).to_string(index=False));print(audit)
