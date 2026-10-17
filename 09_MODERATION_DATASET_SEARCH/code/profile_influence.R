options(stringsAsFactors=FALSE)
suppressPackageStartupMessages(library(glmmTMB))
root<-normalizePath('09_MODERATION_DATASET_SEARCH/bikeshare_profile',winslash='/');out<-file.path(root,'outputs')
b<-readRDS(file.path(out,'full_bundle.rds'));m<-b$models$joint;d<-b$data
rank<-read.csv(file.path(out,'full_influence_approximation.csv'))
dates<-sort(unique(d$dteday));fixed<-dates[unique(round(seq(1,length(dates),length.out=5)))]
selected<-unique(c(head(rank$id,5),fixed))
dir.create(file.path(out,'deletion_models'),showWarnings=FALSE)
cn<-names(fixef(m)$cond);zn<-names(fixef(m)$zi);ci<-grep('context.*:|:.*context',cn);zi<-grep('context.*:|:.*context',zn)
base<-c(fixef(m)$cond[ci],fixef(m)$zi[zi]);base_se<-c(sqrt(diag(vcov(m)$cond))[ci],sqrt(diag(vcov(m)$zi))[zi])
ans<-list();co<-list()
for(date in selected){
 cat('Exact deletion',date,'\n');flush.console();dd<-droplevels(d[d$dteday!=date,]);path<-file.path(out,'deletion_models',paste0(date,'.rds'))
 if(file.exists(path))mm<-readRDS(path) else{
  start<-lapply(split(m$fit$par,names(m$fit$par)),unname)
  mm<-tryCatch(glmmTMB(formula(m,component='cond'),ziformula=formula(m,component='zi'),family=nbinom2,data=dd,start=start,control=glmmTMBControl(optCtrl=list(iter.max=1200,eval.max=1600,rel.tol=1e-10))),error=function(e)e)
  saveRDS(mm,path)
 }
 if(inherits(mm,'glmmTMB')){
  est<-c(fixef(mm)$cond[ci],fixef(mm)$zi[zi]);VV<-vcov(mm,full=TRUE);nn<-colnames(VV);ix<-which(grepl('context.*:|:.*context',nn));bb<-c(fixef(mm)$cond,fixef(mm)$zi);names(bb)<-c(cn,paste0('zi~',zn));ee<-bb[nn[ix]];wald<-as.numeric(t(ee)%*%solve(VV[ix,ix],ee))
  a<-data.frame(date=date,selection=if(date%in%head(rank$id,5))'top approximate influence' else 'fixed calendar position',convergence=mm$fit$convergence,pdHess=mm$sdr$pdHess,gradient=max(abs(mm$sdr$gradient.fixed)),max_shift_model_SE=max(abs((est-base)/base_se)),joint_Wald=wald,df=length(ix),p=pchisq(wald,length(ix),lower.tail=FALSE))
  co[[date]]<-data.frame(date=date,term=c(paste0('count_',cn[ci]),paste0('inflation_',zn[zi])),estimate=unname(est),shift=unname(est-base))
 }else a<-data.frame(date=date,selection='error',convergence=NA,pdHess=FALSE,gradient=NA,max_shift_model_SE=NA,joint_Wald=NA,df=length(base),p=NA)
 ans[[date]]<-a;print(a);write.csv(do.call(rbind,ans),file.path(out,'exact_deletion_audit.csv'),row.names=FALSE)
 if(length(co))write.csv(do.call(rbind,co),file.path(out,'exact_deletion_coefficients.csv'),row.names=FALSE)
}
