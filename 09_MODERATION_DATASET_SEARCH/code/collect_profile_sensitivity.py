from pathlib import Path
import pandas as pd
root=Path(__file__).resolve().parents[1]/'bikeshare_profile/outputs'
for stem in ['sensitivity_audit','sensitivity_tests','sensitivity_component_tests']:
    files=list(root.glob(stem+'_*.csv'))
    files=[p for p in files if not (stem=='sensitivity_tests' and p.name.startswith('sensitivity_tests_component'))]
    if files:
        d=pd.concat([pd.read_csv(p) for p in files],ignore_index=True)
        d=d.drop_duplicates(['model','component'] if 'component' in d else ['model'],keep='last')
        if stem!='sensitivity_audit' and (root/'sensitivity_audit.csv').exists():
            audit=pd.read_csv(root/'sensitivity_audit.csv')
            valid=audit.loc[audit.convergence.eq(0)&audit.pdHess.astype(str).str.lower().eq('true'),'model']
            d['interpretable']=d.model.isin(valid)
            d.loc[~d.interpretable,['Wald','p']]=float('nan')
        d.to_csv(root/(stem+'.csv'),index=False)
        print(stem,d.to_string(index=False))
