from pathlib import Path
import zipfile, io, pandas as pd, numpy as np
root=Path(__file__).resolve().parents[1]/'rwm'
raw=zipfile.ZipFile(root/'source/rwm-data.zip').read('rwm.data')
(root/'source/rwm.data').write_bytes(raw)
names='id female year age hsat handdum handper hhninc hhkids educ married haupts reals fachhs abitur univ working bluec whitec self beamt docvis hospvis public addon'.split()
d=pd.read_csv(io.BytesIO(raw),sep=r'\s+',header=None,names=names)
p=pd.read_csv(root/'source/Health.csv')
print(d.head().to_string());print(d.shape)
for var in ['hsat','handdum','handper','educ']:
    v=d[var];print(var,v.value_counts().head(15).to_dict());print('nonlattice',np.sum(np.abs(v*2-np.round(v*2))>1e-6))
for var in ['id','female','year','age','hsat','handdum','handper','educ','docvis','hospvis']:
    print('compare',var,float(np.max(np.abs(d[var]-p[var]))))
print('income scale',np.max(np.abs(d.hhninc*1000-p.hhinc)))
d.to_csv(root/'source/original_numeric.csv',index=False)
