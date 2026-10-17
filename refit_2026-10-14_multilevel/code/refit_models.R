suppressPackageStartupMessages({
  library(data.table)
  library(glmmTMB)
  library(parallel)
})
options(width=140)
data.table::setDTthreads(1L)
args <- commandArgs(trailingOnly=TRUE)
dataset <- if (length(args)) args[1] else stop("Specify ccd or nncs")
stopifnot(dataset %in% c("ccd", "nncs"))
script_arg <- grep("^--file=", commandArgs(), value=TRUE)
script_path <- normalizePath(sub("^--file=", "", script_arg[1]), winslash="/")
root <- normalizePath(file.path(dirname(script_path), "../.."), winslash="/")
out <- file.path(root, "refit_2026-10-14_multilevel", "outputs", dataset)
dir.create(file.path(out,"models"), recursive=TRUE, showWarnings=FALSE)
dir.create(file.path(out,"logs"), recursive=TRUE, showWarnings=FALSE)

scale_record <- function(x) as.numeric((x-mean(x))/sd(x))
sample_rows <- list()
scale_rows <- list()
describe <- function(d, name, group) {
  sizes <- table(d[[group]])
  sample_rows[[name]] <<- data.table(sample=name,n=nrow(d),groups=length(sizes),
    min_group=min(sizes),median_group=median(sizes),max_group=max(sizes),
    zero_n=sum(d$y==0),zero_pct=100*mean(d$y==0),
    metros=if("metro" %in% names(d)) uniqueN(d$metro) else NA_integer_)
}
record_scale <- function(sample,variable,values,basis) {
  scale_rows[[paste(sample,variable,sep="_")]] <<- data.table(sample,variable,basis,
    mean=mean(values),sd=sd(values))
}

if(dataset=="ccd") {
  raw <- fread(file.path(root,"14_CCD_LEA_2009/raw_data/ag092a.txt"),
    sep="\t",quote="",encoding="Latin-1",na.strings=c("M","N",""))
  raw[, state:=sprintf("%02d",as.integer(FIPST))]
  raw[, `:=`(rural=as.integer(ULOCAL09 %in% c(41,42,43)),
    city=as.integer(ULOCAL09 %in% c(11,12,13)),small=as.integer(MEMBER09<500),
    one_school=as.integer(SCH09==1),type2=as.integer(TYPE09==2))]
  eligible <- raw[as.integer(FIPST)<=56 & TYPE09 %in% c(1,2) & MEMBER09>0 & SCH09>0]
  prepare_ccd <- function(pool,name,focal="rural") {
    d <- copy(pool)
    d <- d[,if(.N>=10) .SD,by=state]
    d[, context_share:=mean(get(focal)),by=state]
    d[, within:=get(focal)-context_share]
    state_values <- unique(d[,.(state,context_share)])
    record_scale(name,"context",state_values$context_share,"distinct eligible states")
    d[, context_z:=(context_share-mean(state_values$context_share))/sd(state_values$context_share)]
    d[, `:=`(log_enrollment=log(MEMBER09),log_schools=log(SCH09))]
    record_scale(name,"log_enrollment",d$log_enrollment,"eligible districts before missing outcome exclusion")
    record_scale(name,"log_schools",d$log_schools,"eligible districts before missing outcome exclusion")
    d[, `:=`(log_enrollment_z=scale_record(log_enrollment),log_schools_z=scale_record(log_schools))]
    # Component-specific random effect; nonunion districts have a zero design column.
    d[, union_component:=as.numeric(type2==1 & !is.na(UNION09) & as.character(UNION09)!="000" & as.character(UNION09)!="0")]
    d[, union_key:=ifelse(union_component==1,paste0(state,":",UNION09),"nonunion_zero_design")]
    d <- d[is.finite(ELL09) & ELL09>=0]
    d[, `:=`(y=as.integer(ELL09),state=factor(state),union_key=factor(union_key))]
    stopifnot(!anyDuplicated(d$LEAID),all(d$MEMBER09>0),all(d$y==round(d$y)),
      all(d[,uniqueN(context_share),by=state]$V1==1))
    describe(d,name,"state")
    fwrite(d[,.(LEAID,state,TYPE09,UNION09,ELL09,MEMBER09,SCH09,rural,small,context_share,within,context_z)],
      file.path(out,paste0("sample_",name,".csv")))
    d
  }
  datasets <- list(
    primary=prepare_ccd(eligible[state!="50"],"primary"),
    include_vt=prepare_ccd(eligible,"include_vt"),
    type1=prepare_ccd(eligible[TYPE09==1],"type1"),
    small=prepare_ccd(eligible[state!="50"],"small","small"))
  controls <- "log_enrollment_z + log_schools_z + city + small + one_school + type2"
  make_spec <- function(id,sample="primary",ci=TRUE,zi=TRUE,quad=TRUE,
                        random="(1|state)",family="ZINB",focal="rural",zi_random="(1|state)") {
    controls_here <- if(focal=="small") "log_enrollment_z + log_schools_z + rural + city + one_school + type2" else controls
    control_names <- strsplit(controls_here," + ",fixed=TRUE)[[1]]
    control_names <- control_names[vapply(control_names,function(v)uniqueN(datasets[[sample]][[v]])>1,logical(1))]
    controls_here <- paste(control_names,collapse=" + ")
    base <- paste("within + context_z +",if(quad) "I(context_z^2) +" else "",controls_here)
    list(id=id,sample=sample,cond=as.formula(paste("y ~",base,
      if(ci) "+ within:context_z" else "","+ offset(log_enrollment) +",random)),
      zi=if(family=="NB") ~0 else as.formula(paste("~",base,
      if(zi) "+ within:context_z" else "","+",zi_random)),
      family=family,target="within:context_z")
  }
  specs <- list(
    make_spec("primary_additive",ci=FALSE,zi=FALSE),
    make_spec("primary_count",zi=FALSE),
    make_spec("primary_inflation",ci=FALSE),
    make_spec("primary_joint"),
    make_spec("primary_nb",family="NB"),
    make_spec("include_vt_joint","include_vt"),
    make_spec("type1_joint","type1"),
    make_spec("linear_context_joint",quad=FALSE),
    make_spec("state_random_slope_joint",random="diag(1+within|state)"),
    make_spec("both_random_slopes_joint",random="diag(1+within|state)",zi_random="diag(1+within|state)"),
    make_spec("union_dependence_joint",random="(1|state) + diag(0+union_component|union_key)"),
    make_spec("small_secondary_joint","small",focal="small"))
} else {
  raw <- fread(file.path(root,"NNCS data/DS0002/38483-0002-Data.tsv"),
    na.strings="",strip.white=TRUE,
    colClasses=list(character=c("CITY_ID","STATE","T_COUNTY","TRACT2","METROID2")))
  annual <- paste0("T_MRD",10:13)
  required <- c("T_POP102","T_DSDC2","T_PMIN2","T_RSI22","T_PVAC2",annual)
  d <- raw[complete.cases(raw[,..required])]
  d[, y:=rowSums(.SD),.SDcols=annual]
  fractional_cities <- d[abs(y-round(y))>1e-4,unique(CITY_ID)]
  d <- d[!CITY_ID %in% fractional_cities & !is.na(C_HGINI2) & T_POP102>0]
  d[, `:=`(y=as.integer(round(y)),partial=as.integer(T_PRTFL2),
    tract_geoid=paste0(sprintf("%02d",as.integer(STATE)),sprintf("%03d",as.integer(T_COUNTY)),
      sprintf("%06d",as.integer(TRACT2))))]
  d[, tract_city_id:=paste(CITY_ID,tract_geoid,sep=":")]
  stopifnot(nrow(d)==6849,uniqueN(d$CITY_ID)==67,!anyDuplicated(d$tract_city_id),
    all(d[,uniqueN(C_HGINI2),by=CITY_ID]$V1==1),all(d[,uniqueN(METROID2),by=CITY_ID]$V1==1))
  prepare_nncs <- function(pool,name) {
    x <- copy(pool)
    x[, city_mean:=mean(T_DSDC2),by=CITY_ID]
    x[, deviation:=T_DSDC2-city_mean]
    cv <- unique(x[,.(CITY_ID,C_HGINI2,city_mean)])
    record_scale(name,"context",cv$C_HGINI2,"distinct cities")
    record_scale(name,"between_disadvantage",cv$city_mean,"distinct cities")
    record_scale(name,"within_disadvantage",x$deviation,"pooled within-city deviations; no additional mean subtraction")
    x[, `:=`(within=deviation/sd(deviation),
      between=(city_mean-mean(cv$city_mean))/sd(cv$city_mean),
      context_z=(C_HGINI2-mean(cv$C_HGINI2))/sd(cv$C_HGINI2),
      log_exposure=log(T_POP102*4),city=factor(CITY_ID),metro=factor(METROID2))]
    for(v in c("T_PMIN2","T_RSI22","T_PVAC2")) {
      label <- c(T_PMIN2="minority",T_RSI22="instability",T_PVAC2="vacancy")[[v]]
      x[,(paste0(label,"_z")):=scale_record(get(v))]
      x[,(paste0(label,"_mean")):=mean(get(v)),by=city]
      means <- unique(x[,c("CITY_ID",paste0(label,"_mean")),with=FALSE])[[2]]
      deviations <- x[[v]]-x[[paste0(label,"_mean")]]
      record_scale(name,label,x[[v]],"tract-city records")
      record_scale(name,paste0(label,"_between"),means,"distinct cities")
      record_scale(name,paste0(label,"_within"),deviations,"pooled within-city deviations")
      x[,(paste0(label,"_b")):=(get(paste0(label,"_mean"))-mean(means))/sd(means)]
      x[,(paste0(label,"_w")):=(get(v)-get(paste0(label,"_mean")))/sd(deviations)]
    }
    stopifnot(max(abs(x[,mean(within),by=city]$V1))<1e-10,
      all(x[,uniqueN(context_z),by=city]$V1==1))
    describe(x,name,"city")
    fwrite(x[,.(tract_city_id,tract_geoid,CITY_ID,CITY,METROID2,partial,y,T_POP102,T_DSDC2,
      city_mean,deviation,within,between,C_HGINI2,context_z)],file.path(out,paste0("sample_",name,".csv")))
    x
  }
  datasets <- list(primary=prepare_nncs(d,"primary"),whole=prepare_nncs(d[partial==0],"whole"))
  make_spec <- function(id,sample="primary",ci=TRUE,zi=TRUE,between_int=TRUE,
                       random="(1|city)",zi_random="(1|city)",family="ZINB",all_decompose=FALSE) {
    ctl <- if(all_decompose) "minority_w + minority_b + instability_w + instability_b + vacancy_w + vacancy_b" else
      "minority_z + instability_z + vacancy_z"
    base <- paste("within + between + context_z +",ctl,
      if(sample!="whole") "+ partial" else "",if(between_int) "+ between:context_z" else "")
    list(id=id,sample=sample,cond=as.formula(paste("y ~",base,if(ci) "+ within:context_z" else "",
      "+ offset(log_exposure) +",random)),
      zi=if(family=="NB") ~0 else as.formula(paste("~",base,if(zi) "+ within:context_z" else "",
        if(nzchar(zi_random)) paste("+",zi_random) else "")),family=family,target="within:context_z")
  }
  specs <- list(
    make_spec("primary_additive",ci=FALSE,zi=FALSE),
    make_spec("primary_count",zi=FALSE),
    make_spec("primary_inflation",ci=FALSE),
    make_spec("primary_joint"),
    make_spec("primary_nb",family="NB"),
    make_spec("fixed_inflation_joint",zi_random=""),
    make_spec("metro_dependence_joint",random="(1|city) + (1|metro)"),
    make_spec("whole_joint","whole"),
    make_spec("city_random_slope_joint",random="diag(1+within|city)"),
    make_spec("additive_between_joint",between_int=FALSE),
    make_spec("all_covariates_decomposed_joint",all_decompose=TRUE))
  fwrite(data.table(CITY_ID=fractional_cities),file.path(out,"excluded_fractional_cities.csv"))
}
saveRDS(datasets,file.path(out,"analysis_datasets.rds"),compress="xz")
saveRDS(specs,file.path(out,"model_specs.rds"))
fwrite(rbindlist(sample_rows),file.path(out,"sample_summary.csv"))
fwrite(rbindlist(scale_rows),file.path(out,"scaling.csv"))
fwrite(rbindlist(lapply(specs,function(s)data.table(model=s$id,sample=s$sample,
  count_formula=paste(deparse(s$cond),collapse=" "),inflation_formula=paste(deparse(s$zi),collapse=" "),
  family=s$family,target=s$target))),file.path(out,"model_specifications.csv"))
writeLines(capture.output(sessionInfo()),file.path(out,"session_info.txt"))

fit_job <- function(spec,datasets,out) {
  data.table::setDTthreads(1L)
  model_path <- file.path(out,"models",paste0(spec$id,".rds"))
  cached <- if(file.exists(model_path)) readRDS(model_path) else NULL
  if(!is.null(cached) && "max_newton_step_se" %in% names(cached$metrics) && isTRUE(cached$metrics$acceptable)) return(cached$metrics)
  logfile <- file.path(out,"logs",paste0(spec$id,".txt"))
  cat(format(Sys.time()),"START OR RESUME",spec$id,"\n",file=logfile,append=file.exists(logfile))
  warnings_seen <- if(!is.null(cached)) cached$warnings else character()
  t0 <- proc.time()[[3]]
  d <- datasets[[spec$sample]]
  anchor_path <- file.path(out,"models","primary_joint.rds")
  anchor <- if(file.exists(anchor_path)) tryCatch(readRDS(anchor_path),error=function(e)NULL) else NULL
  starts <- NULL
  if(!is.null(anchor$model)) {
    a <- anchor$model
    fixed_formula <- if(any(grepl("diag(",deparse(spec$cond),fixed=TRUE))) anchor$spec$cond else spec$cond
    beta_names <- colnames(model.matrix(lme4::nobars(fixed_formula),d))
    beta <- setNames(rep(0,length(beta_names)),beta_names)
    common <- intersect(names(beta),names(fixef(a)$cond))
    beta[common] <- fixef(a)$cond[common]
    starts <- list(beta=unname(beta),betadisp=unname(fixef(a)$disp))
    if(spec$family!="NB") {
      zi_fixed_formula <- if(any(grepl("diag(",deparse(spec$zi),fixed=TRUE))) anchor$spec$zi else spec$zi
      zi_names <- colnames(model.matrix(lme4::nobars(zi_fixed_formula),d))
      betazi <- setNames(rep(0,length(zi_names)),zi_names)
      common <- intersect(names(betazi),names(fixef(a)$zi))
      betazi[common] <- fixef(a)$zi[common]
      starts$betazi <- unname(betazi)
    }
    bars <- function(f)vapply(lme4::findbars(f),function(x)paste(deparse(x),collapse=""),character(1))
    if(identical(bars(spec$cond),bars(anchor$spec$cond))) starts$theta <- unname(a$fit$par[names(a$fit$par)=="theta"])
    if(spec$family!="NB" && identical(bars(spec$zi),bars(anchor$spec$zi))) starts$thetazi <- unname(a$fit$par[names(a$fit$par)=="thetazi"])
  }
  attempt <- function(optimizer) {
    ctl <- if(optimizer=="nlminb") glmmTMBControl(optCtrl=list(iter.max=3000,eval.max=4000,rel.tol=1e-10),parallel=1L) else
      glmmTMBControl(optimizer=optim,optArgs=list(method="BFGS"),optCtrl=list(maxit=3000),parallel=1L)
    withCallingHandlers(tryCatch(glmmTMB(spec$cond,ziformula=spec$zi,data=d,
      family=nbinom2(),control=ctl,start=starts),error=function(e)e),
      warning=function(w){warnings_seen <<- c(warnings_seen,paste(optimizer,conditionMessage(w)));invokeRestart("muffleWarning")})
  }
  diagnostics <- function(m) {
    if(is.null(m)||inherits(m,"error")) return(list(ok=FALSE,code=NA_integer_,pd=FALSE,gradient=Inf,scaled=Inf,newton=Inf,ll=-Inf))
    gvec <- tryCatch(m$obj$gr(m$fit$par),error=function(e)Inf)
    g <- max(abs(gvec)); cv <- m$sdr$cov.fixed
    scaled <- newton <- Inf
    if(isTRUE(m$sdr$pdHess)&&!is.null(cv)&&nrow(cv)==length(gvec)&&all(is.finite(cv))&&all(diag(cv)>0)) {
      step <- cv %*% gvec
      scaled <- max(abs(step)/sqrt(diag(cv)))
      decrement2 <- as.numeric(crossprod(gvec,step))
      if(is.finite(decrement2)&&decrement2>=0) newton <- sqrt(decrement2)
    }
    list(ok=m$fit$convergence==0 && isTRUE(m$sdr$pdHess) && is.finite(scaled) && scaled<.01 && newton<.01,
      code=m$fit$convergence,pd=isTRUE(m$sdr$pdHess),gradient=g,scaled=scaled,newton=newton,ll=as.numeric(logLik(m)))
  }
  initial_optimizer <- if(basename(out)=="nncs" && !is.null(anchor$model)) "BFGS" else "nlminb"
  m1 <- if(!is.null(cached$model)) cached$model else attempt(initial_optimizer)
  optimizer <- if(!is.null(cached$model)) cached$metrics$optimizer else initial_optimizer
  warm_path <- file.path(out,paste0("warm_",spec$id,".rds"))
  if(file.exists(warm_path)) {
    warm <- readRDS(warm_path)$model
    if(diagnostics(warm)$ok && (!diagnostics(m1)$ok || as.numeric(logLik(warm))>=as.numeric(logLik(m1)))) {
      m1 <- warm; optimizer <- "warm_nlminb"
    }
  }
  dg1 <- diagnostics(m1)
  chosen <- m1; dg <- dg1
  attempts <- data.table(optimizer=optimizer,convergence=dg1$code,pd_hessian=dg1$pd,
    max_gradient=dg1$gradient,max_newton_step_se=dg1$scaled,newton_decrement=dg1$newton,
    logLik=dg1$ll,acceptable=dg1$ok,criterion="curvature-scaled score")
  if(!is.null(cached)) {
    old <- copy(cached$attempts); old[,criterion:="initial raw-gradient rule"]
    attempts <- rbindlist(list(old,attempts),fill=TRUE)
  }
  if(!dg1$ok) {
    fallback_optimizer <- if(optimizer=="BFGS") "nlminb" else "BFGS"
    cat(format(Sys.time()),"RETRY",fallback_optimizer,"\n",file=logfile,append=TRUE)
    m2 <- attempt(fallback_optimizer); dg2 <- diagnostics(m2)
    attempts <- rbindlist(list(attempts,data.table(optimizer=fallback_optimizer,convergence=dg2$code,pd_hessian=dg2$pd,
      max_gradient=dg2$gradient,max_newton_step_se=dg2$scaled,newton_decrement=dg2$newton,
      logLik=dg2$ll,acceptable=dg2$ok,criterion="curvature-scaled score")),fill=TRUE)
    if((dg2$ok && !dg1$ok) || (dg2$ok && dg1$ok && dg2$ll>dg1$ll+1e-6) ||
       (!dg1$ok && !dg2$ok && dg2$pd && !dg1$pd)) {
      chosen <- m2; dg <- dg2; optimizer <- fallback_optimizer
    }
  }
  if(inherits(chosen,"error")) {
    metrics <- data.table(model=spec$id,sample=spec$sample,family=spec$family,n=nrow(d),
      AIC=NA_real_,BIC=NA_real_,logLik=NA_real_,df=NA_integer_,convergence=NA_integer_,
      pd_hessian=FALSE,max_gradient=Inf,max_newton_step_se=Inf,newton_decrement=Inf,acceptable=FALSE,optimizer=optimizer,
      elapsed_seconds=proc.time()[[3]]-t0,error=conditionMessage(chosen))
    coefs <- random <- data.table()
    chosen <- NULL
  } else {
    metrics <- data.table(model=spec$id,sample=spec$sample,family=spec$family,n=nrow(d),
      AIC=AIC(chosen),BIC=BIC(chosen),logLik=as.numeric(logLik(chosen)),df=attr(logLik(chosen),"df"),
      convergence=dg$code,pd_hessian=dg$pd,max_gradient=dg$gradient,
      max_newton_step_se=dg$scaled,newton_decrement=dg$newton,acceptable=dg$ok,
      optimizer=optimizer,elapsed_seconds=proc.time()[[3]]-t0,error="")
    coefs <- rbindlist(lapply(c("cond","zi"),function(comp) {
      mat <- summary(chosen)$coefficients[[comp]]
      if(is.null(mat)||nrow(mat)==0) return(NULL)
      data.table(model=spec$id,sample=spec$sample,component=comp,term=rownames(mat),
        estimate=mat[,1],se=mat[,2],z=mat[,3],p=mat[,4],
        lower=mat[,1]-qnorm(.975)*mat[,2],upper=mat[,1]+qnorm(.975)*mat[,2],
        multiplier=exp(mat[,1]),multiplier_lower=exp(mat[,1]-qnorm(.975)*mat[,2]),
        multiplier_upper=exp(mat[,1]+qnorm(.975)*mat[,2]))
    }),fill=TRUE)
    vc <- VarCorr(chosen)
    random <- rbindlist(lapply(c("cond","zi"),function(comp)rbindlist(lapply(names(vc[[comp]]),function(g) {
      sd <- attr(vc[[comp]][[g]],"stddev")
      data.table(model=spec$id,component=comp,group=g,term=names(sd),sd=as.numeric(sd),near_boundary=as.numeric(sd)<1e-4)
    }),fill=TRUE)),fill=TRUE)
  }
  result <- list(spec=spec,metrics=metrics,coefficients=coefs,random_effects=random,
    attempts=attempts,warnings=unique(warnings_seen),model=chosen)
  if(!is.null(cached)) {
    backup <- file.path(out,"initial_checkpoints",basename(model_path))
    dir.create(dirname(backup),showWarnings=FALSE)
    if(!file.exists(backup)) file.copy(model_path,backup)
  }
  saveRDS(result,model_path,compress="xz")
  fwrite(metrics,file.path(out,"logs",paste0(spec$id,"_metrics.csv")))
  cat(format(Sys.time()),"DONE",capture.output(print(metrics)),paste(unique(warnings_seen),collapse="\n"),
    "\n",file=logfile,append=TRUE,sep="\n")
  metrics
}

cores <- min(if(dataset=="nncs") 3L else 2L,length(specs))
cl <- makeCluster(cores)
clusterEvalQ(cl,{suppressPackageStartupMessages({library(data.table);library(glmmTMB)});data.table::setDTthreads(1L);NULL})
clusterExport(cl,c("fit_job","datasets","out"),envir=environment())
cat("Fitting",dataset,length(specs),"models with",cores,"workers\n")
print(parLapplyLB(cl,specs,function(s)fit_job(s,datasets,out),chunk.size=1L))
stopCluster(cl)

results <- lapply(specs,function(s) {
  r <- readRDS(file.path(out,"models",paste0(s$id,".rds")))
  r$model <- NULL
  r$spec <- list(id=r$spec$id)
  r
})
metrics <- rbindlist(lapply(results,`[[`,"metrics"),fill=TRUE)
coef_table <- rbindlist(lapply(results,`[[`,"coefficients"),fill=TRUE)
random_table <- rbindlist(lapply(results,`[[`,"random_effects"),fill=TRUE)
fwrite(metrics,file.path(out,"model_comparison.csv"))
fwrite(coef_table,file.path(out,"coefficients.csv"))
fwrite(coef_table[term=="within:context_z"],file.path(out,"within_interactions.csv"))
fwrite(coef_table[term=="between:context_z"],file.path(out,"between_interactions.csv"))
fwrite(random_table,file.path(out,"random_effects.csv"))
fwrite(rbindlist(lapply(results,function(r)cbind(model=r$spec$id,r$attempts)),fill=TRUE),file.path(out,"optimizer_attempts.csv"))

tests <- data.table(reduced=c("primary_additive","primary_additive","primary_count","primary_inflation"),
  full=c("primary_count","primary_inflation","primary_joint","primary_joint"),
  test=c("Add count interaction","Add inflation interaction","Add inflation given count interaction","Add count given inflation interaction"))
lrt <- rbindlist(lapply(seq_len(nrow(tests)),function(i) {
  a <- metrics[model==tests$reduced[i]]; b <- metrics[model==tests$full[i]]
  lr <- 2*(b$logLik-a$logLik); df <- b$df-a$df
  data.table(test=tests$test[i],reduced=a$model,full=b$model,n=a$n,
    LR=lr,df=df,p=if(is.finite(lr)&&lr>=-1e-5&&df>0) pchisq(max(lr,0),df,lower.tail=FALSE) else NA_real_,
    valid_numerics=a$acceptable&&b$acceptable,delta_AIC=b$AIC-a$AIC)
}))
fwrite(lrt,file.path(out,"likelihood_ratio_tests.csv"))
cat("COMPLETE",dataset,"\n")
print(metrics)
print(coef_table[term=="within:context_z",.(model,component,estimate,se,p,lower,upper)])
print(lrt)
