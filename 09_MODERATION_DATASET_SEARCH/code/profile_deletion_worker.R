options(stringsAsFactors=FALSE)
suppressPackageStartupMessages(library(glmmTMB))
out<-'09_MODERATION_DATASET_SEARCH/bikeshare_profile/outputs'
b<-readRDS(file.path(out,'full_bundle.rds'));m<-b$models$joint;d<-b$data
rank<-read.csv(file.path(out,'full_influence_approximation.csv'));dates<-sort(unique(d$dteday))
selected<-unique(c(head(rank$id,5),dates[unique(round(seq(1,length(dates),length.out=5)))]))
args<-as.integer(commandArgs(trailingOnly=TRUE));positions<-seq(args[1],args[2])
for(k in positions){
 date<-selected[k];path<-file.path(out,'deletion_models',paste0(date,'.rds'));if(file.exists(path))next
 cat('Parallel exact deletion',k,date,'\n');flush.console()
 dd<-droplevels(d[d$dteday!=date,]);start<-lapply(split(m$fit$par,names(m$fit$par)),unname)
 mm<-tryCatch(glmmTMB(formula(m,component='cond'),ziformula=formula(m,component='zi'),family=nbinom2,data=dd,start=start,control=glmmTMBControl(optCtrl=list(iter.max=1200,eval.max=1600,rel.tol=1e-10))),error=function(e)e)
 temporary<-paste0(path,'.worker');saveRDS(mm,temporary);stopifnot(file.rename(temporary,path))
}
