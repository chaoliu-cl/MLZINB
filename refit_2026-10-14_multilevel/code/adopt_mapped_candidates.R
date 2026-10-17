suppressPackageStartupMessages({library(data.table);library(glmmTMB)})
out <- "refit_2026-10-14_multilevel/outputs/nncs"
for(id in c("primary_additive","primary_inflation")) {
  path<-file.path(out,paste0("mapped_candidate_",id,".rds"))
  if(!file.exists(path)) next
  r<-readRDS(path);m<-r$model
  g<-m$obj$gr(m$fit$par);cv<-m$sdr$cov.fixed
  scaled<-newton<-Inf
  if(isTRUE(m$sdr$pdHess)&&all(is.finite(cv))&&all(diag(cv)>0)) {
    step<-cv%*%g;scaled<-max(abs(step)/sqrt(diag(cv)));newton<-sqrt(as.numeric(crossprod(g,step)))
  }
  ok<-m$fit$convergence==0&&isTRUE(m$sdr$pdHess)&&is.finite(scaled)&&scaled<.01&&newton<.01
  cat(id,"AIC",AIC(m),"scaled",scaled,"newton",newton,"acceptable",ok,"\n")
  metrics<-data.table(model=id,sample="primary",family="ZINB",n=nrow(m$frame),AIC=AIC(m),BIC=BIC(m),
    logLik=as.numeric(logLik(m)),df=attr(logLik(m),"df"),convergence=m$fit$convergence,pd_hessian=m$sdr$pdHess,
    max_gradient=max(abs(g)),max_newton_step_se=scaled,newton_decrement=newton,acceptable=ok,
    optimizer="bounded_nlminb_mapped",elapsed_seconds=r$elapsed,error="")
  coef<-rbindlist(lapply(c("cond","zi"),function(comp) {
    mat<-summary(m)$coefficients[[comp]]
    if(is.null(mat)||!nrow(mat))return(NULL)
    tab<-data.table(model=id,sample="primary",component=comp,term=rownames(mat),estimate=mat[,1],se=mat[,2],z=mat[,3],p=mat[,4])
    tab<-tab[is.finite(se)&se>0]
    tab[,`:=`(lower=estimate-qnorm(.975)*se,upper=estimate+qnorm(.975)*se,multiplier=exp(estimate),
      multiplier_lower=exp(estimate-qnorm(.975)*se),multiplier_upper=exp(estimate+qnorm(.975)*se))]
    tab
  }),fill=TRUE)
  if(!ok) coef[,c("estimate","se","z","p","lower","upper","multiplier","multiplier_lower","multiplier_upper"):=NA_real_]
  vc<-VarCorr(m)
  random<-rbindlist(lapply(c("cond","zi"),function(comp)rbindlist(lapply(names(vc[[comp]]),function(group) {
    sd<-attr(vc[[comp]][[group]],"stddev")
    data.table(model=id,component=comp,group=group,term=names(sd),sd=as.numeric(sd),near_boundary=as.numeric(sd)<1e-4)
  }),fill=TRUE)),fill=TRUE)
  finalpath<-file.path(out,"models",paste0(id,".rds"))
  if(file.exists(finalpath)) {
    dir.create(file.path(out,"failed_checkpoints"),showWarnings=FALSE)
    file.copy(finalpath,file.path(out,"failed_checkpoints",basename(finalpath)),overwrite=FALSE)
  }
  result<-list(spec=r$spec,model=m,coefficients=coef,metrics=metrics,random_effects=random,
    warnings=r$warnings,mapped_formulas=list(cond=r$mapped_cond,zi=r$mapped_zi),
    attempts=data.table(optimizer="bounded_nlminb_mapped",convergence=m$fit$convergence,pd_hessian=m$sdr$pdHess,
      max_gradient=max(abs(g)),max_newton_step_se=scaled,newton_decrement=newton,logLik=as.numeric(logLik(m)),
      acceptable=ok,criterion="curvature-scaled score; specified interaction mapped to zero"))
  saveRDS(result,finalpath,compress=FALSE)
  fwrite(metrics,file.path(out,"logs",paste0(id,"_metrics.csv")))
}
