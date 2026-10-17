suppressPackageStartupMessages({library(data.table);library(glmmTMB)})
root <- normalizePath("refit_2026-10-14_multilevel/outputs",winslash="/")
curvature <- function(m) {
  if(is.null(m)) return(list(g=Inf,scaled=Inf,newton=Inf,ok=FALSE))
  gvec <- tryCatch(m$obj$gr(m$fit$par),error=function(e)rep(Inf,length(m$fit$par)))
  g <- max(abs(gvec)); cv <- m$sdr$cov.fixed
  scaled <- newton <- Inf
  if(isTRUE(m$sdr$pdHess)&&!is.null(cv)&&nrow(cv)==length(gvec)&&all(is.finite(cv))&&all(diag(cv)>0)) {
    step <- cv %*% gvec
    scaled <- max(abs(step)/sqrt(diag(cv)))
    d2 <- as.numeric(crossprod(gvec,step))
    if(is.finite(d2)&&d2>=0) newton <- sqrt(d2)
  }
  list(g=g,scaled=scaled,newton=newton,ok=isTRUE(m$fit$convergence==0)&&isTRUE(m$sdr$pdHess)&&scaled<.01&&newton<.01)
}
for(ds in c("ccd","nncs")) {
  out <- file.path(root,ds)
  paths <- list.files(file.path(out,"models"),pattern="\\.rds$",full.names=TRUE)
  rows <- list(); coefs <- list(); random <- list(); attempts <- list()
  for(path in paths) {
    r <- readRDS(path); id <- r$spec$id; m <- r$model
    z <- if(all(c("max_newton_step_se","newton_decrement") %in% names(r$metrics)))
      list(g=r$metrics$max_gradient,scaled=r$metrics$max_newton_step_se,newton=r$metrics$newton_decrement,
        ok=r$metrics$acceptable) else curvature(m)
    met <- copy(r$metrics)
    met[,`:=`(max_gradient=z$g,max_newton_step_se=z$scaled,newton_decrement=z$newton,
      acceptable=z$ok,criterion="optimizer code 0; positive-definite Hessian; Newton correction and decrement < 0.01")]
    rows[[id]] <- met
    if(nrow(r$coefficients)) coefs[[id]] <- r$coefficients
    if(nrow(r$random_effects)) random[[id]] <- r$random_effects
    if(nrow(r$attempts)) attempts[[id]] <- cbind(model=id,r$attempts)
    rm(r,m);gc(verbose=FALSE)
  }
  metrics <- rbindlist(rows,fill=TRUE); coef_table <- rbindlist(coefs,fill=TRUE); random_table <- rbindlist(random,fill=TRUE)
  fwrite(metrics,file.path(out,"model_comparison.csv")); fwrite(coef_table,file.path(out,"coefficients.csv"))
  fwrite(coef_table[term=="within:context_z"],file.path(out,"within_interactions.csv"))
  fwrite(coef_table[term=="between:context_z"],file.path(out,"between_interactions.csv"))
  fwrite(random_table,file.path(out,"random_effects.csv")); fwrite(rbindlist(attempts,fill=TRUE),file.path(out,"optimizer_attempts.csv"))
  tests <- data.table(reduced=c("primary_additive","primary_additive","primary_count","primary_inflation"),
    full=c("primary_count","primary_inflation","primary_joint","primary_joint"),
    test=c("Add count interaction","Add inflation interaction","Add inflation given count interaction","Add count given inflation interaction"))
  lrt <- rbindlist(lapply(seq_len(nrow(tests)),function(i) {
    a<-metrics[model==tests$reduced[i]];b<-metrics[model==tests$full[i]]
    if(nrow(a)!=1||nrow(b)!=1) return(data.table(test=tests$test[i],reduced=tests$reduced[i],full=tests$full[i],n=NA_integer_,LR=NA_real_,df=NA_integer_,p=NA_real_,valid_numerics=FALSE,delta_AIC=NA_real_))
    lr<-2*(b$logLik-a$logLik);df<-b$df-a$df
    data.table(test=tests$test[i],reduced=a$model,full=b$model,n=a$n,LR=lr,df=df,
      p=if(is.finite(lr)&&lr>=-1e-5&&df>0)pchisq(max(lr,0),df,lower.tail=FALSE) else NA_real_,
      valid_numerics=isTRUE(a$acceptable)&&isTRUE(b$acceptable),delta_AIC=b$AIC-a$AIC)
  })); fwrite(lrt,file.path(out,"likelihood_ratio_tests.csv"))
  cat(ds,"finalized",nrow(metrics),"models; acceptable",sum(metrics$acceptable),"\n")
}
