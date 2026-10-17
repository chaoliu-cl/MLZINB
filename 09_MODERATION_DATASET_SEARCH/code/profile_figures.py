from pathlib import Path
import numpy as np,pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.ticker import PercentFormatter

root=Path(__file__).resolve().parents[1]/'bikeshare_profile';out=root/'outputs';fig=root/'figures';fig.mkdir(exist_ok=True)
plt.rcParams.update({'font.family':'DejaVu Sans','font.size':10,'axes.spines.top':False,'axes.spines.right':False,'figure.dpi':130})
colors={0:'#247BA0',1:'#C65B32'};labels={0:'Nonworking day',1:'Working day'}
metrics={'mu':'Count-process mean μ','pi':'Modeled structural-zero probability π','expected':'Expected observed casual rentals','total_zero':'Total probability of zero rentals'}
def save(f,name):
    f.savefig(fig/(name+'.png'),dpi=180,bbox_inches='tight',facecolor='white')
    f.savefig(fig/(name+'.pdf'),bbox_inches='tight',facecolor='white');plt.close(f)

d=pd.read_csv(out/'analysis_data.csv')
f,ax=plt.subplots(1,3,figsize=(12,3.6))
g=d.drop_duplicates('dteday');v=g.groupby(['yr','context']).size().unstack();v.index=['2011 discovery','2012 validation'];v.rename(columns=labels).plot.bar(ax=ax[0],color=[colors[0],colors[1]],rot=0)
ax[0].set(ylabel='Complete calendar days',xlabel='',title='Day-level context support');ax[0].legend(fontsize=8)
for ctx in [0,1]:
    t=d[d.context.eq(ctx)].groupby('hr').y.mean();ax[1].plot(t.index,t,label=labels[ctx],color=colors[ctx])
    t=d[d.context.eq(ctx)].groupby('hr').y.apply(lambda x:x.eq(0).mean());ax[2].plot(t.index,t,label=labels[ctx],color=colors[ctx])
ax[1].set(title='Observed hourly mean',xlabel='Clock hour',ylabel='Casual rentals per recorded hour');ax[2].set(title='Observed zero fraction',xlabel='Clock hour');ax[2].yaxis.set_major_formatter(PercentFormatter(1))
for a in ax[1:]:a.set_xticks([0,6,12,18,23])
f.suptitle('A balanced multilevel structure: 24 hours within each of 655 days',y=1.03,fontsize=13);f.tight_layout();save(f,'structure_and_observed_patterns')

if (out/'component_predictions.csv').exists():
    pred=pd.read_csv(out/'component_predictions.csv')
    f,axes=plt.subplots(2,2,figsize=(11.5,7),sharex=True)
    for ax,(metric,title) in zip(axes.flat,metrics.items()):
        for ctx in [0,1]:
            t=pred[pred.metric.eq(metric)&pred.context.eq(ctx)].sort_values('hour')
            ax.plot(t.hour,t.value,color=colors[ctx],label=labels[ctx],lw=1.8)
            ax.fill_between(t.hour.to_numpy(),t.lower.to_numpy(),t.upper.to_numpy(),color=colors[ctx],alpha=.16)
        ax.set(title=title);ax.set_xticks([0,6,12,18,23]);ax.grid(alpha=.18)
        if metric in ['pi','total_zero']:ax.yaxis.set_major_formatter(PercentFormatter(1))
    for ax in axes[-1]:ax.set_xlabel('Clock hour')
    f.suptitle('Working-day context changes the within-day rental profile',fontsize=15,y=.995)
    f.legend(*axes[0,0].get_legend_handles_labels(),loc='lower center',ncol=2,bbox_to_anchor=(.5,.035),frameon=False)
    f.text(.06,.012,'Full ML-ZINB; day effects set to zero; equal-day empirical standardization. Bands: pointwise 95% calendar-HAC (14-day) intervals.',fontsize=8)
    f.tight_layout(rect=(0,.09,1,.96));save(f,'component_predictions')
    ct=pd.read_csv(out/'workingday_contrasts.csv')
    f,axes=plt.subplots(2,2,figsize=(11.5,7),sharex=True)
    for ax,(metric,title) in zip(axes.flat,metrics.items()):
        a=ct[ct.metric.eq(metric)&ct.model.eq('joint')];z=ct[ct.metric.eq(metric)&ct.model.eq('additive')]
        ax.axhline(0,color='gray',lw=.8);ax.plot(a.hour,a.contrast,color='#61599B',label='Joint model',lw=1.8)
        ax.fill_between(a.hour.to_numpy(),a.lower.to_numpy(),a.upper.to_numpy(),color='#61599B',alpha=.18)
        ax.plot(z.hour,z.contrast,color='#444444',ls='--',label='Additive model',lw=1.4)
        ax.set(title=title,ylabel='Working minus nonworking');ax.set_xticks([0,6,12,18,23]);ax.grid(alpha=.16)
    for ax in axes[-1]:ax.set_xlabel('Clock hour')
    f.suptitle('Observable contrasts and the additive-model comparison',fontsize=15,y=.995)
    f.legend(*axes[0,0].get_legend_handles_labels(),loc='lower center',ncol=2,bbox_to_anchor=(.5,.035),frameon=False)
    f.text(.06,.012,'Curves use a common reference distribution and zero day effects. Response-scale variation alone is not an interaction test.',fontsize=8)
    f.tight_layout(rect=(0,.09,1,.96));save(f,'context_contrasts')

for kind in ['primary','random_slope','flexible_hour_joint','varying_dispersion']:
    folder=out/'diagnostics'/kind
    if not (folder/'calibration.csv').exists():continue
    cal=pd.read_csv(folder/'calibration.csv');f,axes=plt.subplots(1,3,figsize=(12.5,4))
    for ax,metric,title in zip(axes,['mean_y','zero_fraction','positive_mean'],['Mean rentals','Zero fraction','Mean among positive counts']):
        for ctx in [0,1]:
            a=cal[cal.metric.eq(metric)&cal.context.eq(ctx)].sort_values('hour');x=a.hour.to_numpy()+(-.15 if ctx==0 else .15)
            ax.vlines(x,a.lower,a.upper,color=colors[ctx],alpha=.7,lw=2)
            ax.scatter(x,a.observed,color=colors[ctx],s=25,label=labels[ctx],zorder=3)
            ax.plot(x,a.simulation_median,color=colors[ctx],ls='--',lw=1.2)
        ax.set(title=title,xlabel='Mean hour in time band');ax.grid(alpha=.15)
        if metric=='zero_fraction':ax.yaxis.set_major_formatter(PercentFormatter(1))
    f.suptitle('Observed outcomes and unconditional model simulations: '+kind.replace('_',' '),y=1.03,fontsize=13)
    f.legend(*axes[0].get_legend_handles_labels(),loc='lower center',ncol=2,bbox_to_anchor=(.5,-.05),frameon=False)
    f.text(.02,-.08,'Points: observed. Dashed: simulation median. Bars: 95% envelope from 500 simulations with fresh day effects.',fontsize=8)
    f.tight_layout();save(f,'calibration_'+kind)
    r=pd.read_csv(folder/'residuals.csv');h=r.groupby(['context','hour']).residual.mean().reset_index();ac=pd.read_csv(folder/'calendar_residual_correlations.csv')
    f,axes=plt.subplots(1,2,figsize=(10.5,3.6))
    for ctx in [0,1]:
        a=h[h.context.eq(ctx)];axes[0].plot(a.hour,a.residual,color=colors[ctx],label=labels[ctx])
    axes[0].axhline(.5,color='gray',ls='--');axes[0].set(title='Mean scaled residual by hour',xlabel='Clock hour',ylabel='Mean DHARMa residual');axes[0].legend(fontsize=8)
    axes[1].bar(ac.lag,ac.correlation,color='#247BA0');axes[1].axhline(0,color='gray');axes[1].set(title='Day residual dependence',xlabel='Calendar-day lag',ylabel='Residual correlation')
    f.suptitle('Remaining model discrepancies: '+kind.replace('_',' '),y=1.03);f.tight_layout();save(f,'residual_patterns_'+kind)

if (out/'full_influence_approximation.csv').exists():
    inf=pd.read_csv(out/'full_influence_approximation.csv').head(20).iloc[::-1];f,ax=plt.subplots(figsize=(8,6))
    ax.barh(inf.id,inf.max_model_se_shift,color='#247BA0');ax.set(xlabel='Largest approximate coefficient shift / model SE',title='Twenty most influential days: first-order deletion approximation')
    f.tight_layout();save(f,'influential_days')

if (out/'sensitivity_tests.csv').exists():
    tests=pd.read_csv(out/'sensitivity_tests.csv');audit=pd.read_csv(out/'sensitivity_audit.csv')
    tests=tests.merge(audit[['model','pdHess','convergence']],on='model')
    tests['logp']=-np.log10(tests.p.clip(lower=1e-300));f,ax=plt.subplots(figsize=(9,5))
    c=['#247BA0' if bool(h) and v==0 else '#C65B32' for h,v in zip(tests.pdHess,tests.convergence)]
    ax.barh(tests.model.str.replace('_',' '),tests.logp,color=c);ax.axvline(-np.log10(.05),color='gray',ls='--')
    for y,row in enumerate(tests.itertuples()):
        if pd.isna(row.p):ax.text(3,y,'Not interpretable: failed Hessian',va='center',fontsize=9,color='#C65B32')
    ax.set(xlabel='−log10(p), truncated at 300',title='Contextual profile tests across specifications')
    f.text(.02,.01,'Different clock-time bases imply different test dimensions. Numerical flags are retained in the accompanying audit.',fontsize=8)
    f.tight_layout(rect=(0,.04,1,1));save(f,'sensitivity_tests')
print('Figures written to',fig)
