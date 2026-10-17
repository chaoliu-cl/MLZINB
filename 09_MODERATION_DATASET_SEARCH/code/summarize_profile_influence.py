from pathlib import Path
import numpy as np,pandas as pd,json
out=Path(__file__).resolve().parents[1]/'bikeshare_profile/outputs'
exact=pd.read_csv(out/'exact_deletion_coefficients.csv');approx=pd.read_csv(out/'full_influence_approximation.csv').set_index('id')
X=pd.read_csv(out/'score_inputs/full/X.csv');Z=pd.read_csv(out/'score_inputs/full/Z.csv')
cov=np.loadtxt(out/'score_inputs/full/covariance.csv',delimiter=',')
lookup={**{'count_'+x:i for i,x in enumerate(X.columns)},**{'inflation_'+x:X.shape[1]+i for i,x in enumerate(Z.columns)}}
rows=[]
for row in exact.itertuples():
    a=float(approx.loc[row.date,row.term+'_shift']);sd=float(np.sqrt(cov[lookup[row.term],lookup[row.term]]))
    rows.append(dict(date=row.date,term=row.term,exact_shift=row.shift,approximate_shift=a,model_se=sd,exact_shift_in_SE=row.shift/sd,approximate_shift_in_SE=a/sd,approximation_error_in_SE=(row.shift-a)/sd))
d=pd.DataFrame(rows);d.to_csv(out/'deletion_approximation_check.csv',index=False)
summary=dict(exact_dates=int(d.date.nunique()),coefficients_per_date=6,maximum_absolute_exact_shift_in_model_SE=float(d.exact_shift_in_SE.abs().max()),maximum_absolute_approximation_error_in_model_SE=float(d.approximation_error_in_SE.abs().max()),correlation_of_standardized_shifts=float(d.exact_shift_in_SE.corr(d.approximate_shift_in_SE)))
(out/'deletion_approximation_summary.json').write_text(json.dumps(summary,indent=2));print(summary)
