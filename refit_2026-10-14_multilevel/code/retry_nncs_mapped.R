suppressPackageStartupMessages({library(data.table);library(glmmTMB)})
args <- commandArgs(trailingOnly=TRUE)
id <- args[1]
out <- "refit_2026-10-14_multilevel/outputs/nncs"
specs <- readRDS(file.path(out,"model_specs.rds"))
spec <- specs[[which(vapply(specs,function(s)s$id==id,logical(1)))]]
anchor <- readRDS(file.path(out,"models","primary_joint.rds"))
dat <- readRDS(file.path(out,"analysis_datasets.rds"))$primary
needed <- unique(c(all.vars(anchor$spec$cond),all.vars(anchor$spec$zi)))
dat <- as.data.frame(dat[,needed,with=FALSE])
m0 <- anchor$model
start <- lapply(split(m0$fit$par,names(m0$fit$par)),unname)
cond_names <- names(fixef(m0)$cond);zi_names<-names(fixef(m0)$zi)
idx <- which(cond_names=="within:context_z")
start$beta[idx] <- 0
bm <- seq_along(start$beta);bm[idx]<-NA
map <- list(beta=factor(bm))
if(id=="primary_additive") {
  idx <- which(zi_names=="within:context_z")
  start$betazi[idx]<-0
  zm <- seq_along(start$betazi);zm[idx]<-NA
  map$betazi<-factor(zm)
}
warnings_seen<-character()
t0<-proc.time()[3]
bounded_optimizer <- function(par,fn,gr,control=list(),...) {
  lo<-rep(-30,length(par));hi<-rep(30,length(par))
  v<-names(par)%in%c("theta","thetazi")
  lo[v]<- -5;hi[v]<-2
  v<-names(par)=="betadisp";lo[v]<- -5;hi[v]<-5
  result<-nlminb(start=par,objective=fn,gradient=gr,lower=lo,upper=hi,
    control=list(iter.max=1000,eval.max=1500,rel.tol=1e-10),...)
  cat("Bounded optimizer largest normalized distance:",max(abs(result$par)/(1+abs(hi))),"\n")
  if(any(result$par<lo+1e-5|result$par>hi-1e-5)) warning("A numerical bound is active")
  result
}
ctrl <- glmmTMBControl(optimizer=bounded_optimizer,parallel=1L)
m<-withCallingHandlers(glmmTMB(anchor$spec$cond,ziformula=anchor$spec$zi,
  data=dat,family=nbinom2(),start=start,map=map,control=ctrl),warning=function(w){warnings_seen<<-c(warnings_seen,conditionMessage(w));invokeRestart("muffleWarning")})
cat("elapsed",proc.time()[3]-t0,"conv",m$fit$convergence,"pd",m$sdr$pdHess,"AIC",AIC(m),"\n")
print(summary(m)$coefficients)
saveRDS(list(model=m,spec=spec,mapped_cond=anchor$spec$cond,mapped_zi=anchor$spec$zi,
  warnings=warnings_seen,elapsed=proc.time()[3]-t0),file.path(out,paste0("mapped_candidate_",id,".rds")),compress="xz")
