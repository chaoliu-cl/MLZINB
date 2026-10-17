options(stringsAsFactors=FALSE)
suppressPackageStartupMessages(library(glmmTMB))
root<-normalizePath('09_MODERATION_DATASET_SEARCH/bikeshare_profile',winslash='/');out<-file.path(root,'outputs')
b<-readRDS(file.path(out,'full_bundle.rds'));d<-b$data;m<-b$models$joint
dir.create(file.path(out,'sensitivity_models'),showWarnings=FALSE)
f<-formula(m,component='cond');z<-formula(m,component='zi')
fcat0<-y~factor(hr)+context+factor(mnth)+yr+temp+I(temp^2)+hum+windspeed+badweather+(1|group)
fcat1<-update(fcat0,.~.+factor(hr):context)
if(!'yr'%in%all.vars(f)) {fcat0<-update(fcat0,.~.-yr);fcat1<-update(fcat1,.~.-yr)}
spec<-list(
 random_slope=list(update(f,.~.-(1|group)+(1+sin1+cos1||group)),z,d),
 inflation_intercept=list(f,update(z,~.+(1|group)),d),
 third_count_harmonic=list(update(f,.~.+sin3+cos3+context:sin3+context:cos3),z,d),
 second_inflation_harmonic=list(f,update(z,~.+sin2+cos2+context:sin2+context:cos2),d),
 temperature_context=list(update(f,.~.+temp:context+I(temp^2):context),update(z,~.+temp:context),d),
 flexible_hour_additive=list(fcat0,b$z0,d),
 flexible_hour_joint=list(fcat1,z,d),
 BFGS=list(f,z,d)
)
da<-read.csv('09_MODERATION_DATASET_SEARCH/bikeshare/outputs/analysis_data.csv');da$group<-factor(da$group)
spec$all_released_days<-list(f,z,da)
args<-commandArgs(trailingOnly=TRUE);tag<-if(length(args))args[1] else 'all'
if(length(args)>1)spec<-spec[args[-1]]
audit<-list();tests<-list();component_tests<-list()
for(nm in names(spec)){
 cat('Sensitivity',nm,'\n');flush.console();pp<-spec[[nm]];path<-file.path(out,'sensitivity_models',paste0(nm,'.rds'))
 if(file.exists(path))mm<-readRDS(path) else{
  ctrl<-if(nm=='BFGS')glmmTMBControl(optimizer=optim,optArgs=list(method='BFGS'),optCtrl=list(maxit=1500,reltol=1e-10)) else glmmTMBControl(optCtrl=list(iter.max=1500,eval.max=2000,rel.tol=1e-10))
  st<-if(nm=='BFGS')lapply(split(m$fit$par,names(m$fit$par)),unname) else NULL
  warn<-character();tm<-system.time(mm<-tryCatch(withCallingHandlers(glmmTMB(pp[[1]],ziformula=pp[[2]],family=nbinom2,data=pp[[3]],control=ctrl,start=st),warning=function(e){warn<<-c(warn,conditionMessage(e));invokeRestart('muffleWarning')}),error=function(e)e))['elapsed']
  attr(mm,'warnings_saved')<-warn;attr(mm,'elapsed')<-tm;saveRDS(mm,path)
 }
 if(inherits(mm,'glmmTMB')){
  a<-data.frame(model=nm,rows=nobs(mm),logLik=as.numeric(logLik(mm)),AIC=AIC(mm),convergence=mm$fit$convergence,pdHess=mm$sdr$pdHess,gradient=max(abs(mm$sdr$gradient.fixed)),max_coef=max(abs(c(fixef(mm)$cond,fixef(mm)$zi))),max_se=max(sqrt(diag(mm$sdr$cov.fixed))),elapsed=attr(mm,'elapsed'),warnings=paste(attr(mm,'warnings_saved'),collapse=' | '))
  ix<-grep('context.*:|:.*context',colnames(vcov(mm,full=TRUE)))
  # Select only contextual clock-time products, excluding temperature products.
  nn<-colnames(vcov(mm,full=TRUE));ix<-ix[grepl('sin[123]|cos[123]|factor\\(hr\\)',nn[ix])]
  if(length(ix)){
   VV<-vcov(mm,full=TRUE);bv<-c(fixef(mm)$cond,fixef(mm)$zi);names(bv)<-c(names(fixef(mm)$cond),paste0('zi~',names(fixef(mm)$zi)))
   est<-bv[nn[ix]];stat<-tryCatch(as.numeric(t(est)%*%solve(VV[ix,ix,drop=FALSE],est)),error=function(e)NA_real_)
   tt<-data.frame(model=nm,Wald=stat,df=length(ix),p=pchisq(stat,length(ix),lower.tail=FALSE));tests[[nm]]<-tt;print(tt)
   for(cc in c('count','inflation')){
    ii<-ix[if(cc=='count')!startsWith(nn[ix],'zi~') else startsWith(nn[ix],'zi~')]
    if(length(ii)){ee<-bv[nn[ii]];ww<-tryCatch(as.numeric(t(ee)%*%solve(VV[ii,ii,drop=FALSE],ee)),error=function(e)NA_real_);component_tests[[paste(nm,cc)]]<-data.frame(model=nm,component=cc,Wald=ww,df=length(ii),p=pchisq(ww,length(ii),lower.tail=FALSE))}
   }
  }
  capture.output(summary(mm),file=file.path(out,paste0('sensitivity_',nm,'_summary.txt')))
 }else a<-data.frame(model=nm,rows=nrow(pp[[3]]),logLik=NA,AIC=NA,convergence=NA,pdHess=FALSE,gradient=NA,max_coef=NA,max_se=NA,elapsed=NA,warnings=conditionMessage(mm))
 audit[[nm]]<-a;print(a);flush.console();write.csv(do.call(rbind,audit),file.path(out,paste0('sensitivity_audit_',tag,'.csv')),row.names=FALSE)
 if(length(tests))write.csv(do.call(rbind,tests),file.path(out,paste0('sensitivity_tests_',tag,'.csv')),row.names=FALSE)
 if(length(component_tests))write.csv(do.call(rbind,component_tests),file.path(out,paste0('sensitivity_component_tests_',tag,'.csv')),row.names=FALSE)
}
paths<-file.path(out,'sensitivity_models',paste0(c('flexible_hour_additive','flexible_hour_joint'),'.rds'))
if(all(file.exists(paths))){aa<-readRDS(paths[1]);jj<-readRDS(paths[2]);if(inherits(aa,'glmmTMB')&&inherits(jj,'glmmTMB')){lr<-2*(as.numeric(logLik(jj))-as.numeric(logLik(aa)));df<-attr(logLik(jj),'df')-attr(logLik(aa),'df');write.csv(data.frame(comparison='hour-factor additive -> joint',LR=lr,df=df,p=pchisq(lr,df,lower.tail=FALSE)),file.path(out,'flexible_hour_LR.csv'),row.names=FALSE)}}
