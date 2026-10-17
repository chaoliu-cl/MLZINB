options(stringsAsFactors=FALSE)
suppressPackageStartupMessages(library(glmmTMB))
root<-normalizePath('09_MODERATION_DATASET_SEARCH/bikeshare_profile',winslash='/');out<-file.path(root,'outputs')
b<-readRDS(file.path(out,'full_bundle.rds'));m<-b$models$joint;d<-b$data
path<-file.path(out,'sensitivity_models','varying_dispersion.rds')
if(file.exists(path))mm<-readRDS(path) else{
 st<-lapply(split(m$fit$par,names(m$fit$par)),unname)
 dispname<-names(st)[grepl('betad',names(st))];stopifnot(length(dispname)==1)
 st[[dispname]]<-c(st[[dispname]],rep(0,5))
 warn<-character();tm<-system.time(mm<-tryCatch(withCallingHandlers(glmmTMB(formula(m,component='cond'),ziformula=formula(m,component='zi'),dispformula=~context+sin1+cos1+sin2+cos2,family=nbinom2,data=d,start=st,control=glmmTMBControl(optCtrl=list(iter.max=1500,eval.max=2000,rel.tol=1e-10))),warning=function(e){warn<<-c(warn,conditionMessage(e));invokeRestart('muffleWarning')}),error=function(e)e))['elapsed']
 attr(mm,'elapsed')<-tm;attr(mm,'warnings_saved')<-warn;saveRDS(mm,path)
}
if(inherits(mm,'glmmTMB')){
 a<-data.frame(model='varying_dispersion',rows=nobs(mm),logLik=as.numeric(logLik(mm)),AIC=AIC(mm),convergence=mm$fit$convergence,pdHess=mm$sdr$pdHess,gradient=max(abs(mm$sdr$gradient.fixed)),max_coef=max(abs(c(fixef(mm)$cond,fixef(mm)$zi))),max_se=max(sqrt(diag(mm$sdr$cov.fixed))),elapsed=attr(mm,'elapsed'),warnings=paste(attr(mm,'warnings_saved'),collapse=' | '))
 VV<-vcov(mm,full=TRUE);nn<-colnames(VV);ix<-which(grepl('context.*:|:.*context',nn)&grepl('sin[12]|cos[12]',nn)&!startsWith(nn,'d~'))
 bv<-c(fixef(mm)$cond,fixef(mm)$zi);names(bv)<-c(names(fixef(mm)$cond),paste0('zi~',names(fixef(mm)$zi)))
 # Dispersion has no contextual products, so the selected terms are mean/inflation only.
 ix<-ix[nn[ix]%in%names(bv)]
 ee<-bv[nn[ix]];ww<-as.numeric(t(ee)%*%solve(VV[ix,ix],ee));tt<-data.frame(model='varying_dispersion',Wald=ww,df=length(ix),p=pchisq(ww,length(ix),lower.tail=FALSE))
 ctests<-do.call(rbind,lapply(c('count','inflation'),function(cc){ii<-ix[if(cc=='count')!startsWith(nn[ix],'zi~') else startsWith(nn[ix],'zi~')];ee<-bv[nn[ii]];ww<-as.numeric(t(ee)%*%solve(VV[ii,ii],ee));data.frame(model='varying_dispersion',component=cc,Wald=ww,df=length(ii),p=pchisq(ww,length(ii),lower.tail=FALSE))}))
 write.csv(tt,file.path(out,'sensitivity_tests_D.csv'),row.names=FALSE);write.csv(ctests,file.path(out,'sensitivity_component_tests_D.csv'),row.names=FALSE)
 capture.output(summary(mm),file=file.path(out,'sensitivity_varying_dispersion_summary.txt'));print(tt);print(ctests)
}else a<-data.frame(model='varying_dispersion',rows=nrow(d),logLik=NA,AIC=NA,convergence=NA,pdHess=FALSE,gradient=NA,max_coef=NA,max_se=NA,elapsed=NA,warnings=conditionMessage(mm))
write.csv(a,file.path(out,'sensitivity_audit_D.csv'),row.names=FALSE);print(a)
