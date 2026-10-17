options(stringsAsFactors=FALSE)
suppressPackageStartupMessages(library(glmmTMB))
root<-normalizePath('09_MODERATION_DATASET_SEARCH/bikeshare',winslash='/');out<-file.path(root,'outputs')
dir.create(file.path(out,'models'),showWarnings=FALSE)
d0<-read.csv(file.path(out,'analysis_data.csv'));d0$group<-factor(d0$group)
f0<-y ~ x_w + x_b0 * context + sin1 + cos1 + sin2 + cos2 + factor(mnth) + temp + I(temp^2) + hum + windspeed + badweather + (1|group)
f1<-update(f0,.~.+x_w:context)
z0<-~ x_w + x_b0 * context + sin1 + cos1 + temp + hum + badweather
z1<-update(z0,~.+x_w:context)
ctrl<-glmmTMBControl(optCtrl=list(iter.max=1500,eval.max=2000,rel.tol=1e-10))
spec<-list(additive=list(f0,z0),count=list(f1,z0),inflation=list(f0,z1),joint=list(f1,z1),nb=list(f1,~0))
args<-commandArgs(trailingOnly=TRUE);samples<-if(length(args))args else c('discovery','validation','full')
warm<-function(old,f,z,d){
 if(is.null(old)||!inherits(old,'glmmTMB'))return(NULL)
 st<-lapply(split(old$fit$par,names(old$fit$par)),unname)
 xn<-colnames(model.matrix(lme4::nobars(f),d));zn<-colnames(model.matrix(z,d));bc<-setNames(rep(0,length(xn)),xn);bz<-setNames(rep(0,length(zn)),zn)
 bc[intersect(names(fixef(old)$cond),xn)]<-fixef(old)$cond[intersect(names(fixef(old)$cond),xn)]
 bz[intersect(names(fixef(old)$zi),zn)]<-fixef(old)$zi[intersect(names(fixef(old)$zi),zn)]
 st$beta<-unname(bc);st$betazi<-unname(bz);st
}
for(s in samples){
 d<-if(s=='full')d0 else droplevels(d0[d0$sample==s,]);models<-list();audit<-list()
 for(nm in names(spec)){
  path<-file.path(out,'models',paste0(s,'_',nm,'.rds'));cat('Fitting',s,nm,nrow(d),'rows\n');flush.console()
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
 saveRDS(list(data=d,models=models,f0=f0,f1=f1,z0=z0,z1=z1,control=ctrl),file.path(out,paste0(s,'_bundle.rds')))
}
capture.output(sessionInfo(),file=file.path(out,'session_info.txt'))
