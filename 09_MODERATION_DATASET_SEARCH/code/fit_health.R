options(stringsAsFactors=FALSE)
suppressPackageStartupMessages(library(glmmTMB))
root <- normalizePath('09_MODERATION_DATASET_SEARCH/rwm',winslash='/')
dir.create(file.path(root,'outputs','models'),showWarnings=FALSE)
d0 <- read.csv(file.path(root,'outputs','analysis_data.csv'))
d0$group <- factor(d0$id)
ctrl <- glmmTMBControl(optCtrl=list(iter.max=1200,eval.max=1600))
controls <- paste('x_w + x_bz * female + age_bz + I(age_bz^2) + factor(year)',
 ' + inc_w + inc_bz + work_w + work_b + marry_w + marry_b + kids_w + kids_b',
 ' + pub_w + pub_b + hand_w + hand_b + edu_w + edu_bz')
f0 <- as.formula(paste('y ~',controls,'+ (1|group)'))
f1 <- update(f0,.~.+x_w:female)
z0 <- as.formula(paste('~',controls))
z1 <- update(z0,~.+x_w:female)
spec <- list(additive=list(f0,z0),count=list(f1,z0),inflation=list(f0,z1),joint=list(f1,z1),nb=list(f1,~0))
args <- commandArgs(trailingOnly=TRUE)
samples <- if(length(args))args else c('discovery','validation','full')
for(s in samples){
  d <- if(s=='full') d0 else droplevels(d0[d0$split==s,])
  models <- list(); audit <- list()
  for(nm in names(spec)){
    path <- file.path(root,'outputs','models',paste0(s,'_',nm,'.rds'))
    warnings <- character()
    cat('Fitting',s,nm,nrow(d),'rows\n');flush.console()
    if(file.exists(path))m<-readRDS(path) else {
      start<-NULL
      if(!is.null(models$additive)&&nm!='nb'){
        old<-if(nm=='joint'&&!is.null(models$count))models$count else models$additive
        start<-lapply(split(old$fit$par,names(old$fit$par)),unname)
        xn<-colnames(model.matrix(lme4::nobars(spec[[nm]][[1]]),d));zn<-colnames(model.matrix(spec[[nm]][[2]],d))
        bc<-setNames(rep(0,length(xn)),xn);bz<-setNames(rep(0,length(zn)),zn)
        bc[names(fixef(old)$cond)]<-fixef(old)$cond;bz[names(fixef(old)$zi)]<-fixef(old)$zi
        start$beta<-unname(bc);start$betazi<-unname(bz)
      }
      elapsed<-system.time(m<-tryCatch(withCallingHandlers(glmmTMB(spec[[nm]][[1]],ziformula=spec[[nm]][[2]],family=nbinom2,data=d,control=ctrl,start=start),warning=function(w){warnings<<-c(warnings,conditionMessage(w));invokeRestart('muffleWarning')}),error=function(e)e))['elapsed']
      attr(m,'elapsed')<-elapsed;attr(m,'warnings_saved')<-warnings
      saveRDS(m,path)
    }
    models[[nm]]<-m
    if(inherits(m,'glmmTMB')) {
      a<-data.frame(sample=s,model=nm,rows=nobs(m),people=nlevels(d$group),logLik=as.numeric(logLik(m)),AIC=AIC(m),df=attr(logLik(m),'df'),convergence=m$fit$convergence,pdHess=m$sdr$pdHess,max_abs_gradient=max(abs(m$sdr$gradient.fixed)),warnings=paste(attr(m,'warnings_saved'),collapse=' | '))
      capture.output(summary(m),file=file.path(root,'outputs',paste0(s,'_',nm,'_summary.txt')))
    } else a<-data.frame(sample=s,model=nm,rows=nrow(d),people=nlevels(d$group),logLik=NA,AIC=NA,df=NA,convergence=NA,pdHess=FALSE,max_abs_gradient=NA,warnings=conditionMessage(m))
    audit[[nm]]<-a;print(a);flush.console()
    write.csv(do.call(rbind,audit),file.path(root,'outputs',paste0(s,'_fit_audit.csv')),row.names=FALSE)
  }
  if(all(vapply(models,inherits,logical(1),'glmmTMB'))){
    pairs<-list(c('additive','joint'),c('additive','count'),c('additive','inflation'),c('count','joint'),c('inflation','joint'))
    tests<-do.call(rbind,lapply(pairs,function(p){a<-models[[p[1]]];b<-models[[p[2]]];lr<-2*(as.numeric(logLik(b))-as.numeric(logLik(a)));df<-attr(logLik(b),'df')-attr(logLik(a),'df');data.frame(sample=s,comparison=paste(p,collapse=' -> '),LR=lr,df=df,p=pchisq(lr,df,lower.tail=FALSE))}))
    print(tests);write.csv(tests,file.path(root,'outputs',paste0(s,'interaction_tests.csv')),row.names=FALSE)
  }
  saveRDS(list(data=d,models=models,f0=f0,f1=f1,z0=z0,z1=z1,controls=controls,control=ctrl),file.path(root,'outputs',paste0(s,'_bundle.rds')))
}
capture.output(sessionInfo(),file=file.path(root,'outputs','session_info.txt'))
