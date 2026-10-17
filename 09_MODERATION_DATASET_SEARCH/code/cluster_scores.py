"""Independently reconstruct scalar-random-intercept Laplace likelihood by group.

Finite differences include fixed effects, NB dispersion and random-intercept SD.
The summed scores and likelihood must match glmmTMB before sandwich inference.
"""
from pathlib import Path
import sys,json
import numpy as np
import pandas as pd
from scipy.special import expit,gammaln
from scipy.stats import chi2,norm

def run(sample,candidate='rwm'):
    root=Path(__file__).resolve().parents[1]/candidate/'outputs'
    folder=root/'score_inputs'/sample
    xp=pd.read_csv(folder/'X.csv');zp=pd.read_csv(folder/'Z.csv')
    X=xp.to_numpy();Z=zp.to_numpy()
    d=pd.read_csv(folder/'data.csv'); y=d.y.to_numpy();g=d.group.to_numpy()
    par=pd.read_csv(folder/'parameters.csv');theta=par.value.to_numpy()
    cov=np.loadtxt(folder/'covariance.csv',delimiter=',')
    md=pd.read_csv(folder/'metadata.csv').iloc[0]
    p,q=X.shape[1],Z.shape[1];G=int(md['groups'])
    assert len(theta)==p+q+2
    assert list(par.parameter[:p])==['beta']*p
    assert list(par.parameter[p:p+q])==['betazi']*q
    b0=pd.read_csv(folder/'modes.csv').b.to_numpy()
    zero=y==0
    def groupsum(v):return np.bincount(g,weights=v,minlength=G)
    def evaluate(t,return_details=False):
        eta=X@t[:p];zeta=Z@t[p:p+q];pi=expit(zeta)
        phi=np.exp(t[-2]);sd=np.exp(t[-1]);b=b0.copy()
        const=gammaln(y+phi)-gammaln(phi)-gammaln(y+1)
        def at(bb):
            mu=np.exp(np.clip(eta+bb[g],-50,50))
            lognb=const+phi*(np.log(phi)-np.log(phi+mu))+y*(np.log(mu)-np.log(phi+mu))
            logc=-np.logaddexp(0,zeta)+lognb
            lp=logc.copy();lp[zero]=np.logaddexp(-np.logaddexp(0,-zeta[zero]),logc[zero])
            tau=np.ones_like(y,dtype=float);tau[zero]=np.exp(logc[zero]-lp[zero])
            a=y-(y+phi)*mu/(phi+mu)
            ap=-(y+phi)*phi*mu/(phi+mu)**2
            grad=groupsum(tau*a)-bb/sd**2
            curvature=1/sd**2-groupsum(tau*ap+tau*(1-tau)*a*a)
            value=groupsum(lp)-.5*bb*bb/sd**2-np.log(sd)
            return value,grad,curvature
        for iteration in range(60):
            value,grad,h=at(b)
            if np.max(np.abs(grad))<2e-9:break
            step=grad/np.maximum(h,.1)
            step=np.clip(step,-1,1)
            candidate=b+step
            newval=at(candidate)[0]
            for _ in range(25):
                bad=newval<value-1e-13
                if not bad.any():break
                step[bad]*=.5;candidate=b+step;newval=at(candidate)[0]
            b=candidate
        value,grad,h=at(b)
        if np.max(np.abs(grad))>1e-5 or np.any(h<=0):
            raise RuntimeError(f'Group mode reconstruction failed: gradient={abs(grad).max()}, h={h.min()}')
        marginal=value-.5*np.log(h)
        return (marginal,b,grad) if return_details else marginal
    ll,b,innergrad=evaluate(theta,True)
    ll_error=float(ll.sum()-md.logLik)
    scores=np.empty((G,len(theta)))
    for k in range(len(theta)):
        eps=1e-5*max(1,abs(theta[k]));tp=theta.copy();tm=theta.copy();tp[k]+=eps;tm[k]-=eps
        scores[:,k]=(evaluate(tp)-evaluate(tm))/(2*eps)
    gradient_error=float(np.max(np.abs(scores.sum(axis=0)+par.gradient.to_numpy())))
    audit=dict(sample=sample,groups=G,logLik_reconstruction_error=ll_error,score_sum_max_error=gradient_error,mode_max_difference=float(abs(b-b0).max()),inner_mode_max_gradient=float(abs(innergrad).max()))
    print(audit,flush=True)
    assert abs(ll_error)<1e-5 and gradient_error<.002
    vr=cov@scores.T@scores@cov*G/(G-1)
    np.savetxt(root/f'{sample}_cluster_robust_covariance.csv',vr,delimiter=',')
    np.savez_compressed(root/f'{sample}_group_scores.npz',scores=scores,theta=theta,model_covariance=cov,robust_covariance=vr,ids=pd.read_csv(folder/'modes.csv').id.to_numpy())
    if candidate=='bikeshare_profile':
        ci=[k for k,t in enumerate(xp.columns) if ':' in t and 'context' in t]
        zi=[p+k for k,t in enumerate(zp.columns) if ':' in t and 'context' in t]
        indices=ci+zi
        labels=['count']*len(ci)+['inflation']*len(zi)
        terms=[list(xp.columns)[k] for k in ci]+[list(zp.columns)[k-p] for k in zi]
    else:
        term='x_w:female' if candidate=='rwm' else 'x_w:context'
        indices=[list(xp.columns).index(term),p+list(zp.columns).index(term)]
        ci=indices[:1];zi=indices[1:];labels=['count','inflation'];terms=[term,term]
    estimates=theta[indices];v=vr[np.ix_(indices,indices)]
    stat=float(estimates@np.linalg.solve(v,estimates));pval=float(chi2.sf(stat,len(indices)))
    result=dict(sample=sample,Wald=stat,df=len(indices),p=pval)
    pd.DataFrame([result]).to_csv(root/f'{sample}_cluster_joint_test.csv',index=False)
    rows=[]
    for c,k,term in zip(labels,indices,terms):
        se=float(np.sqrt(vr[k,k]));est=float(theta[k]);rows.append(dict(sample=sample,component=c,term=term,estimate=est,se=se,lower=est-1.96*se,upper=est+1.96*se,p=2*norm.sf(abs(est/se)),ratio_modifier=np.exp(est)))
    pd.DataFrame(rows).to_csv(root/f'{sample}_cluster_interactions.csv',index=False)
    # First-order case-deletion influence; exact checks are run separately.
    delta=-scores@cov
    influence=pd.DataFrame({'id':pd.read_csv(folder/'modes.csv').id})
    for k,term,label in zip(indices,terms,labels):influence[label+'_'+term+'_shift']=delta[:,k]
    influence['max_model_se_shift']=np.max(abs(delta[:,indices])/np.sqrt(np.diag(cov)[indices]),axis=1)
    influence.sort_values('max_model_se_shift',ascending=False).to_csv(root/f'{sample}_influence_approximation.csv',index=False)
    (root/f'{sample}_score_verification.json').write_text(json.dumps(audit,indent=2))
    print(result,rows,flush=True)
    if candidate.startswith('bikeshare'):
        dates=pd.to_datetime(pd.read_csv(folder/'modes.csv').id)
        calendar=pd.date_range(dates.min(),dates.max())
        sc=np.zeros((len(calendar),len(theta)))
        sc[calendar.get_indexer(dates)]=scores
        tests=[];coefficients=[]
        for lag in [7,14,28]:
            meat=sc.T@sc
            for l in range(1,lag+1):
                a=sc[l:].T@sc[:-l];meat+=(1-l/(lag+1))*(a+a.T)
            vh=cov@meat@cov*G/(G-1)
            ev=np.linalg.eigvalsh(vh)
            assert ev.min()>-1e-8
            np.savetxt(root/f'{sample}_HAC{lag}_covariance.csv',vh,delimiter=',')
            v=vh[np.ix_(indices,indices)]
            stat=float(estimates@np.linalg.solve(v,estimates))
            tests.append(dict(sample=sample,lag=lag,component='joint',Wald=stat,df=len(indices),p=float(chi2.sf(stat,len(indices)))))
            for label,ii in [('count',ci),('inflation',zi)]:
                tt=theta[ii];vv=vh[np.ix_(ii,ii)];ww=float(tt@np.linalg.solve(vv,tt));tests.append(dict(sample=sample,lag=lag,component=label,Wald=ww,df=len(ii),p=float(chi2.sf(ww,len(ii)))))
            for c,k,term in zip(labels,indices,terms):
                se=float(np.sqrt(vh[k,k]));est=float(theta[k]);coefficients.append(dict(sample=sample,lag=lag,component=c,term=term,estimate=est,se=se,lower=est-1.96*se,upper=est+1.96*se,p=2*norm.sf(abs(est/se)),ratio_modifier=np.exp(est)))
        pd.DataFrame(tests).to_csv(root/f'{sample}_HAC_joint_tests.csv',index=False)
        pd.DataFrame(coefficients).to_csv(root/f'{sample}_HAC_interactions.csv',index=False)
        print('HAC',tests,flush=True)

if __name__=='__main__':
    args=sys.argv[1:];candidate='bikeshare_profile' if '--profile' in args else 'bikeshare' if '--bike' in args else 'rwm'
    args=[x for x in args if not x.startswith('--')]
    for s in args or ['discovery','validation','full']:run(s,candidate)
