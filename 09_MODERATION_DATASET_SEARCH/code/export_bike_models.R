options(stringsAsFactors=FALSE)
suppressPackageStartupMessages(library(glmmTMB))
args<-commandArgs(trailingOnly=TRUE);profile<-'--profile'%in%args;args<-args[args!='--profile']
root<-normalizePath(file.path('09_MODERATION_DATASET_SEARCH',if(profile)'bikeshare_profile' else 'bikeshare'),winslash='/');out<-file.path(root,'outputs')
samples<-if(length(args))args else c('discovery','validation','full')
for(s in samples){
 b<-readRDS(file.path(out,paste0(s,'_bundle.rds')));m<-b$models$joint;d<-b$data
 dest<-file.path(out,'score_inputs',s);dir.create(dest,recursive=TRUE,showWarnings=FALSE)
 stopifnot(m$fit$convergence==0,isTRUE(m$sdr$pdHess))
 X<-model.matrix(lme4::nobars(formula(m,component='cond')),d)[,names(fixef(m)$cond),drop=FALSE]
 Z<-model.matrix(lme4::nobars(formula(m,component='zi')),d)[,names(fixef(m)$zi),drop=FALSE]
 write.csv(X,file.path(dest,'X.csv'),row.names=FALSE);write.csv(Z,file.path(dest,'Z.csv'),row.names=FALSE)
 write.csv(data.frame(y=d$y,group=as.integer(d$group)-1,id=d$dteday),file.path(dest,'data.csv'),row.names=FALSE)
 write.csv(data.frame(parameter=names(m$fit$par),value=unname(m$fit$par),gradient=m$sdr$gradient.fixed),file.path(dest,'parameters.csv'),row.names=FALSE)
 write.table(m$sdr$cov.fixed,file.path(dest,'covariance.csv'),sep=',',row.names=FALSE,col.names=FALSE)
 rr<-ranef(m)$cond$group;dates<-d$dteday[match(rownames(rr),as.character(d$group))]
 write.csv(data.frame(id=dates,b=rr[,1]),file.path(dest,'modes.csv'),row.names=FALSE)
 write.csv(data.frame(logLik=as.numeric(logLik(m)),sigma=sigma(m),p=ncol(X),q=ncol(Z),groups=nrow(rr)),file.path(dest,'metadata.csv'),row.names=FALSE)
 co<-do.call(rbind,lapply(c('cond','zi'),function(c){a<-summary(m)$coefficients[[c]];data.frame(sample=s,component=c,term=rownames(a),estimate=a[,1],se=a[,2],p=a[,4],row.names=NULL)}))
 write.csv(co,file.path(out,paste0(s,'_coefficients.csv')),row.names=FALSE)
}
