suppressPackageStartupMessages({library(data.table);library(glmmTMB)})
script_arg <- grep("^--file=",commandArgs(),value=TRUE)
root <- normalizePath(file.path(dirname(sub("^--file=","",script_arg[1])),"../.."),winslash="/")
outroot <- file.path(root,"refit_2026-10-14_multilevel","outputs")
summaries <- list()
for(ds in c("ccd","nncs")) {
  out <- file.path(outroot,ds)
  completed <- list.files(file.path(out,"logs"),pattern="_metrics.csv$",full.names=TRUE)
  for(path in completed) {
    id <- sub("_metrics.csv$","",basename(path))
    r <- readRDS(file.path(out,"models",paste0(id,".rds")))
    g <- tryCatch(r$model$obj$gr(r$model$fit$par),error=function(e)NULL)
    cv <- if(!is.null(r$model)) r$model$sdr$cov.fixed else NULL
    scaled <- newton <- NA_real_
    if(!is.null(g)&&!is.null(cv)&&nrow(cv)==length(g)&&all(is.finite(cv))&&all(diag(cv)>0)) {
      step <- cv %*% g
      scaled <- max(abs(step)/sqrt(diag(cv)))
      decrement2 <- as.numeric(crossprod(g,step))
      newton <- if(decrement2>=0) sqrt(decrement2) else NA_real_
    }
    s <- copy(r$metrics)
    s[,`:=`(dataset=ds,max_newton_step_se=scaled,newton_decrement=newton)]
    summaries[[paste(ds,id)]] <- s
    cat("\n",ds,id,"\n")
    print(s[,.(n,AIC,convergence,pd_hessian,max_gradient,acceptable,max_newton_step_se,newton_decrement)])
    print(r$attempts)
    print(r$coefficients[term %in% c("within:context_z","between:context_z"),
      .(component,term,estimate,se,p)])
    print(r$random_effects)
    if(length(r$warnings)) print(r$warnings)
    if(!is.null(r$model)&&nrow(r$model$frame)!=s$n) stop("Model dropped unreported observations: ",ds,id)
  }
}
if(length(summaries)) fwrite(rbindlist(summaries,fill=TRUE),file.path(root,"refit_2026-10-14_multilevel","numerical_audit.csv"))
