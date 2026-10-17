suppressPackageStartupMessages({library(data.table);library(glmmTMB)})
args <- commandArgs(trailingOnly=TRUE)
ds <- args[1]; id <- args[2]
base <- file.path("refit_2026-10-14_multilevel","outputs",ds)
r <- readRDS(file.path(base,"models",paste0(id,".rds")))
d <- readRDS(file.path(base,"analysis_datasets.rds"))[[r$spec$sample]]
starts <- lapply(split(r$model$fit$par,names(r$model$fit$par)),unname)
cat("Warm start parameters:",names(starts),"\n")
t0 <- proc.time()[3]
m <- glmmTMB(r$spec$cond,ziformula=r$spec$zi,data=d,family=nbinom2(),start=starts,
  control=glmmTMBControl(optCtrl=list(iter.max=1000,eval.max=2000,rel.tol=1e-12,x.tol=1e-10),parallel=1L))
g <- m$obj$gr(m$fit$par)
cat("elapsed",proc.time()[3]-t0,"code",m$fit$convergence,"pd",m$sdr$pdHess,
  "max_gradient",max(abs(g)),"AIC",AIC(m),"AIC_before",AIC(r$model),"\n")
print(summary(m)$coefficients)
saveRDS(list(model=m,source=id,elapsed=proc.time()[3]-t0),file.path(base,paste0("warm_",id,".rds")))
