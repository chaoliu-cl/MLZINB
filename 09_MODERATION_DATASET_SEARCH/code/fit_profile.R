options(stringsAsFactors=FALSE)
suppressPackageStartupMessages(library(glmmTMB))
root<-normalizePath('09_MODERATION_DATASET_SEARCH/bikeshare_profile',winslash='/');out<-file.path(root,'outputs')
dir.create(out,showWarnings=FALSE);dir.create(file.path(out,'models'),showWarnings=FALSE)
d0<-read.csv('09_MODERATION_DATASET_SEARCH/bikeshare/outputs/analysis_data.csv')
d0<-d0[d0$complete_day %in% c(TRUE,'True','TRUE','1'),];d0$group<-factor(d0$group)
write.csv(d0,file.path(out,'analysis_data.csv'),row.names=FALSE)
stopifnot(all(table(d0$group)==24),max(abs(tapply(d0$sin1,d0$group,mean)))<1e-12,max(abs(tapply(d0$cos1,d0$group,mean)))<1e-12)
f0<-y ~ sin1 + cos1 + sin2 + cos2 + context + factor(mnth) + temp + I(temp^2) + hum + windspeed + badweather + (1|group)
f1<-update(f0,.~.+context:sin1+context:cos1+context:sin2+context:cos2)
z0<-~sin1+cos1+context+temp+hum+badweather
z1<-update(z0,~.+context:sin1+context:cos1)
ctrl<-glmmTMBControl(optCtrl=list(iter.max=1500,eval.max=2000,rel.tol=1e-10))
spec<-list(additive=list(f0,z0),count=list(f1,z0),inflation=list(f0,z1),joint=list(f1,z1),nb=list(f1,~0))
args<-commandArgs(trailingOnly=TRUE);samples<-if(length(args))args else c('discovery','validation','full')
warm<-function(old,f,z,d){
 if(is.null(old)||!inherits(old,'glmmTMB'))return(NULL)
 st<-lapply(split(old$fit$par,names(old$fit$par)),unname)
 xn<-colnames(model.matrix(lme4::nobars(f),d));zn<-colnames(model.matrix(z,d));bc<-setNames(rep(0,length(xn)),xn);bz<-setNames(rep(0,length(zn)),zn)
 common<-intersect(names(fixef(old)$cond),xn);bc[common]<-fixef(old)$cond[common]
 common<-intersect(names(fixef(old)$zi),zn);bz[common]<-fixef(old)$zi[common]
 st$beta<-unname(bc);st$betazi<-unname(bz);st
}
spec0<-spec
for(s in samples){
 spec<-spec0
 if(s=='full')for(nm in names(spec)){
  spec[[nm]][[1]]<-update(spec[[nm]][[1]],.~.+yr)
  if(nm!='nb')spec[[nm]][[2]]<-update(spec[[nm]][[2]],~.+yr)
 }
 d<-if(s=='full')d0 else droplevels(d0[d0$sample==s,]);models<-list();audit<-list()
 for(nm in names(spec)){
  path<-file.path(out,'models',paste0(s,'_',nm,'.rds'));cat('Fitting profile',s,nm,nrow(d),'rows\n');flush.console()
  if(file.exists(path))m<-readRDS(path) else{
   warnings<-character();old<-if(nm=='joint')models$count else models$additive
   start<-if(nm=='nb')NULL else warm(old,spec[[nm]][[1]],spec[[nm]][[2]],d)
   elapsed<-system.time(m<-tryCatch(withCallingHandlers(glmmTMB(spec[[nm]][[1]],ziformula=spec[[nm]][[2]],family=nbinom2,data=d,control=ctrl,start=start),warning=function(w){warnings<<-c(warnings,conditionMessage(w));invokeRestart('muffleWarning')}),error=function(e)e))['elapsed']
   attr(m,'elapsed')<-elapsed;attr(m,'warnings_saved')<-warnings;saveRDS(m,path)
  }
  models[[nm]]<-m
  if(inherits(m,'glmmTMB')){
   a<-data.frame(sample=s,model=nm,rows=nobs(m),groups=nlevels(d$group),logLik=as.numeric(logLik(m)),AIC=AIC(m),df=attr(logLik(m),'df'),convergence=m$fit$convergence,pdHess=m$sdr$pdHess,max_abs_gradient=max(abs(m$sdr$gradient.fixed)),elapsed=attr(m,'elapsed'),warnings=paste(attr(m,'warnings_saved'),collapse=' | '))
   capture.output(summary(m),file=file.path(out,paste0(s,'_',nm,'_summary.txt')))
  }else a<-data.frame(sample=s,model=nm,rows=nrow(d),groups=nlevels(d$group),logLik=NA,AIC=NA,df=NA,convergence=NA,pdHess=FALSE,max_abs_gradient=NA,elapsed=NA,warnings=conditionMessage(m))
  audit[[nm]]<-a;print(a);flush.console();write.csv(do.call(rbind,audit),file.path(out,paste0(s,'_fit_audit.csv')),row.names=FALSE)
 }
 pairs<-list(c('additive','joint'),c('additive','count'),c('additive','inflation'),c('count','joint'),c('inflation','joint'))
 tests<-do.call(rbind,lapply(pairs,function(p){a<-models[[p[1]]];b<-models[[p[2]]];lr<-2*(as.numeric(logLik(b))-as.numeric(logLik(a)));df<-attr(logLik(b),'df')-attr(logLik(a),'df');data.frame(sample=s,comparison=paste(p,collapse=' -> '),LR=lr,df=df,p=pchisq(lr,df,lower.tail=FALSE))}))
 print(tests);write.csv(tests,file.path(out,paste0(s,'_interaction_tests.csv')),row.names=FALSE)
 saveRDS(list(data=d,models=models,f0=spec$additive[[1]],f1=spec$joint[[1]],z0=spec$additive[[2]],z1=spec$joint[[2]],control=ctrl),file.path(out,paste0(s,'_bundle.rds')))
}
capture.output(sessionInfo(),file=file.path(out,'session_info.txt'))
