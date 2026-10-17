# Reproducible paired Monte Carlo study. See PROTOCOL.md before execution.
options(stringsAsFactors=FALSE)
Sys.setlocale('LC_ALL','C')
suppressPackageStartupMessages({library(glmmTMB); library(data.table); library(sandwich)})

simulation_version <- '2026-10-16-v1'
base_seed <- 16102026L
alpha <- .05

condition_grid <- function() {
  base <- list(suite='core', scenario='null', effect=.0, J=40L, n=30L,
    b_count=0, b_zi=0, zi_intercept=-.55, count_intercept=.7, phi=1.4,
    sd_count=.35, sd_zi=.5, rho=0, slope_sd=0, context_binary=FALSE,
    context_probability=.5, unequal=FALSE, sparse=FALSE, informative=FALSE,
    composition_rho=0, exposure=FALSE, varying_dispersion=FALSE,
    heavy_tail=FALSE, hurdle=FALSE, cluster_ar=0, observation_ar=0,count_family='nbinom2')
  rows <- list(); k <- 0L
  add <- function(label, changes=list(), suite='core') {
    k <<- k+1L; r <- modifyList(base, changes); r$label <- label; r$suite <- suite
    rows[[k]] <<- as.data.frame(r)
  }
  for (s in c('null','additive','NB','inflation','count','same','opposite')) {
    effects <- if(s %in% c('null','additive','NB')) 0 else c(.15,.30)
    for(e in effects) for(des in list(c(40L,30L),c(80L,60L))) {
      bc <- if(s %in% c('count','same','opposite')) e else 0
      bz <- if(s %in% c('inflation','same')) e else if(s=='opposite') -e else 0
      add(sprintf('%s_e%.2f_J%d_n%d',s,e,des[1],des[2]),
          list(scenario=s,effect=e,J=des[1],n=des[2],b_count=bc,b_zi=bz))
    }
  }
  stress <- list(
    few_clusters_null=list(scenario='additive',J=20L),
    few_clusters_dual=list(scenario='opposite',J=20L,b_count=.3,b_zi=-.3),
    more_units_same_clusters=list(scenario='opposite',J=40L,n=60L,b_count=.15,b_zi=-.15),
    more_clusters_same_units=list(scenario='opposite',J=80L,n=30L,b_count=.15,b_zi=-.15),
    many_clusters=list(scenario='opposite',J=160L,n=30L,b_count=.15,b_zi=-.15),
    unequal_null=list(scenario='additive',unequal=TRUE),
    unequal_dual=list(scenario='opposite',unequal=TRUE,b_count=.3,b_zi=-.3),
    sparse_clusters=list(scenario='opposite',unequal=TRUE,sparse=TRUE,b_count=.3,b_zi=-.3),
    informative_size=list(scenario='opposite',unequal=TRUE,informative=TRUE,b_count=.3,b_zi=-.3),
    low_inflation=list(scenario='opposite',zi_intercept=-3.5,b_count=.3,b_zi=-.3),
    high_inflation=list(scenario='opposite',zi_intercept=1.5,b_count=.3,b_zi=-.3),
    low_observed_zeros=list(scenario='opposite',zi_intercept=-3.5,count_intercept=2.5,phi=4,b_count=.3,b_zi=-.3),
    near_NB_boundary=list(scenario='additive',zi_intercept=-7),
    strong_overdispersion=list(scenario='opposite',phi=.45,b_count=.3,b_zi=-.3),
    weak_overdispersion=list(scenario='opposite',phi=8,b_count=.3,b_zi=-.3),
    no_inflation_RE_null=list(scenario='additive',sd_zi=0),
    no_inflation_RE_dual=list(scenario='opposite',sd_zi=0,b_count=.3,b_zi=-.3),
    weak_inflation_RE=list(scenario='opposite',sd_zi=.15,b_count=.3,b_zi=-.3),
    strong_inflation_RE=list(scenario='opposite',sd_zi=.9,b_count=.3,b_zi=-.3),
    weak_inflation_strong_count=list(scenario='opposite',b_count=.3,b_zi=-.08),
    strong_inflation_weak_count=list(scenario='opposite',b_count=.08,b_zi=-.3),
    binary_context=list(scenario='opposite',context_binary=TRUE,b_count=.3,b_zi=-.3),
    imbalanced_binary=list(scenario='opposite',context_binary=TRUE,context_probability=.15,b_count=.3,b_zi=-.3),
    composition_correlation=list(scenario='opposite',composition_rho=.7,b_count=.3,b_zi=-.3),
    positive_RE_correlation=list(scenario='opposite',rho=.6,b_count=.3,b_zi=-.3),
    negative_RE_correlation=list(scenario='opposite',rho=-.6,b_count=.3,b_zi=-.3),
    random_slope_null=list(scenario='additive',slope_sd=.3),
    random_slope_dual=list(scenario='opposite',slope_sd=.3,b_count=.3,b_zi=-.3),
    variable_exposure=list(scenario='opposite',exposure=TRUE,b_count=.3,b_zi=-.3),
    variable_dispersion=list(scenario='opposite',varying_dispersion=TRUE,b_count=.3,b_zi=-.3),
    heavy_tailed_RE=list(scenario='opposite',heavy_tail=TRUE,b_count=.3,b_zi=-.3),
    NB1_count_truth=list(scenario='opposite',count_family='nbinom1',b_count=.3,b_zi=-.3),
    hurdle_truth=list(scenario='opposite',hurdle=TRUE,b_count=.3,b_zi=-.3),
    ordered_cluster_null=list(scenario='additive',cluster_ar=.6),
    ordered_cluster_dual=list(scenario='opposite',cluster_ar=.6,b_count=.3,b_zi=-.3),
    within_cluster_dependence=list(scenario='opposite',observation_ar=.6,b_count=.3,b_zi=-.3)
  )
  for(nm in names(stress)) add(nm,stress[[nm]],'stress')
  d <- rbindlist(rows); d[, condition_id:=seq_len(.N)]
  d[, truth_class:=fifelse(b_count!=0 & b_zi!=0,'both',
      fifelse(b_count!=0,'count',fifelse(b_zi!=0,'inflation','neither')))]
  d[,generating_class:=truth_class]
  d[hurdle==TRUE,truth_class:='undefined_hurdle']
  d[, component_defined:=!hurdle & scenario!='NB']
  d[, estimand_status:=fifelse(hurdle,'observable_only_hurdle',
      fifelse(scenario=='NB','inflation_undefined_NB','working_ZINB_parameters'))]
  d[, misspecified:=rho!=0|heavy_tail|hurdle|cluster_ar!=0|observation_ar!=0|
      varying_dispersion|informative|slope_sd>0|count_family!='nbinom2']
  d[]
}

quadrature <- function(n=13L) {
  M <- matrix(0,n,n); M[cbind(1:(n-1),2:n)] <- sqrt(1:(n-1))
  M <- M+t(M); ev <- eigen(M,symmetric=TRUE)
  o <- order(ev$values); list(nodes=ev$values[o],weights=ev$vectors[1,o]^2)
}
gh <- quadrature()

ar_draw <- function(n,rho) {
  if(!rho) return(rnorm(n))
  as.numeric(arima.sim(list(ar=rho),n=n,sd=sqrt(1-rho^2)))
}

generate_data <- function(c,seed) {
  set.seed(seed)
  z <- if(c$context_binary) rbinom(c$J,1,c$context_probability) else rnorm(c$J)
  uc <- ar_draw(c$J,c$cluster_ar)
  uz <- c$rho*uc+sqrt(1-c$rho^2)*ar_draw(c$J,c$cluster_ar)
  # Contaminated normals have heavy tails AND finite exponential moments.
  # Student-t intercepts would imply an infinite marginal count mean.
  if(c$heavy_tail) {
    uc <- rnorm(c$J)*ifelse(runif(c$J)<.1,3,1)/sqrt(1.8)
    uz <- rnorm(c$J)*ifelse(runif(c$J)<.1,3,1)/sqrt(1.8)
  }
  ns <- rep(c$n,c$J)
  if(c$unequal) ns <- pmax(3L,round(c$n*exp(.65*rnorm(c$J)-.65^2/2)))
  if(c$sparse) ns[seq_len(ceiling(c$J*.2))] <- 3L
  if(c$informative) ns <- pmax(3L,round(c$n*exp(.65*uc-.65^2/2)))
  idx <- rep(seq_len(c$J),ns); N <- length(idx)
  zs <- if(c$context_binary)(z-c$context_probability)/sqrt(c$context_probability*(1-c$context_probability)) else z
  mx <- .5*(c$composition_rho*zs+sqrt(1-c$composition_rho^2)*rnorm(c$J))
  xw <- rnorm(N); xw <- xw-ave(xw,idx,FUN=mean)
  d <- data.frame(group=factor(idx,levels=seq_len(c$J)),context=z[idx],mean_x=mx[idx],
     xw=xw,covariate=rbinom(N,1,.45),exposure=if(c$exposure)exp(rnorm(N,0,.6)) else 1)
  d$x_raw <- d$xw+d$mean_x; d$off <- log(d$exposure)
  ep <- linear_predictors(c,d)
  us <- c$slope_sd*rnorm(c$J)
  eps <- rep(0,N)
  if(c$observation_ar) eps <- unlist(lapply(ns,function(n) .35*ar_draw(n,c$observation_ar)))
  mu <- exp(ep$count+c$sd_count*uc[idx]+us[idx]*d$xw+eps)
  pi <- if(c$scenario=='NB') rep(0,N) else plogis(ep$zi+c$sd_zi*uz[idx])
  phi <- if(c$varying_dispersion) c$phi*exp(.4*d$xw+.25*d$context) else rep(c$phi,N)
  if(c$count_family=='nbinom1')phi<-mu/c$phi
  y <- rnbinom(N,mu=mu,size=phi)
  if(c$hurdle) {
    # Exact inverse-CDF zero truncation, never relabel NB zeros as missing.
    p0 <- dnbinom(0,mu=mu,size=phi)
    y <- qnbinom(p0+(1-p0)*runif(N),mu=mu,size=phi)
    y[y<1] <- 1
  }
  structural <- rbinom(N,1,pi); d$y <- ifelse(structural==1L,0,y)
  attr(d,'audit') <- data.frame(N=N,J=c$J,min_n=min(ns),max_n=max(ns),
    zero_rate=mean(d$y==0),structural_fraction=mean(structural),mean=mean(d$y),
    variance=var(d$y),mean_pi=mean(pi),sd_xw=sd(d$xw),context_support=length(unique(z)),
    within_mean_error=max(abs(tapply(d$xw,d$group,mean))),
    all_zero_cluster_fraction=mean(tapply(d$y,d$group,function(v)all(v==0))),
    context_mean=mean(z),context_sd=sd(z),context_min=min(z),context_max=max(z))
  d
}

linear_predictors <- function(c,d) {
  cc <- if(c$scenario %in% c('null','NB')) 0 else .15
  cz <- if(c$scenario %in% c('null','NB')) 0 else .3
  list(count=c$count_intercept+.4*d$xw+cc*d$context+.25*d$covariate+
      .15*d$mean_x+.1*d$mean_x*d$context+c$b_count*d$xw*d$context+d$off,
       zi=c$zi_intercept-.8*d$xw+cz*d$context+.35*d$covariate+
      .15*d$mean_x+.1*d$mean_x*d$context+c$b_zi*d$xw*d$context)
}

# Integrated new-cluster predictions for an NB2 mixture; correlated intercepts
# enter truth only. The fitted models have independent component random effects.
integrated <- function(eta,zeta,phi,vc,vz,covcz=0,hurdle=FALSE,NB=FALSE,nodes=gh,count_family='nbinom2') {
  N <- length(eta); ans <- matrix(0,N,4,dimnames=list(NULL,c('mu','pi','expected','total_zero')))
  sc <- sqrt(pmax(0,vc)); sz <- sqrt(pmax(0,vz))
  rho <- ifelse(sc*sz>0,pmax(-.999,pmin(.999,covcz/pmax(sc*sz,1e-20))),0)
  if(all(rho==0)&&!hurdle) {
    # Factorization makes full-parameter numerical differentiation much faster.
    # E(mu) is exact for a Gaussian intercept/slope distribution.
    em<-exp(eta+vc/2); ez<-ep0<-rep(0,N)
    for(i in seq_along(nodes$nodes)) {
      mu<-exp(eta+sc*nodes$nodes[i])
      size<-if(count_family=='nbinom1')mu/phi else phi
      ep0<-ep0+nodes$weights[i]*exp(-size*log1p(mu/size))
      if(!NB)ez<-ez+nodes$weights[i]*plogis(zeta+sz*nodes$nodes[i])
    }
    return(cbind(mu=em,pi=ez,expected=(1-ez)*em,total_zero=ez+(1-ez)*ep0))
  }
  for(i in seq_along(nodes$nodes)) for(j in seq_along(nodes$nodes)) {
    w <- nodes$weights[i]*nodes$weights[j]
    mu <- exp(eta+sc*nodes$nodes[i])
    pi <- if(NB) rep(0,N) else plogis(zeta+sz*(rho*nodes$nodes[i]+sqrt(1-rho^2)*nodes$nodes[j]))
    size<-if(count_family=='nbinom1')mu/phi else phi
    p0 <- exp(-size*log1p(mu/size))
    ey <- if(hurdle) (1-pi)*mu/pmax(1-p0,1e-15) else (1-pi)*mu
    pz <- if(hurdle) pi else pi+(1-pi)*p0
    ans <- ans+w*cbind(mu,pi,ey,pz)
  }
  ans
}

reference_data <- function(c,seed,n=96L) {
  set.seed(seed)
  z <- if(c$context_binary) rbinom(n,1,c$context_probability) else pmax(-2.5,pmin(2.5,rnorm(n)))
  zs<-if(c$context_binary)(z-c$context_probability)/sqrt(c$context_probability*(1-c$context_probability)) else z
  mx <- .5*(c$composition_rho*zs+sqrt(1-c$composition_rho^2)*rnorm(n))
  d <- data.frame(xw=pmax(-2.5,pmin(2.5,rnorm(n))),context=z,mean_x=mx,
    covariate=rbinom(n,1,.45),exposure=if(c$exposure)exp(rnorm(n,0,.6)) else 1)
  d$x_raw <- d$xw+d$mean_x; d$off <- log(d$exposure); d
}

truth_predictions <- function(c,d,nodes=gh) {
  ep <- linear_predictors(c,d)
  phi <- if(c$varying_dispersion) c$phi*exp(.4*d$xw+.25*d$context) else rep(c$phi,nrow(d))
  if(c$heavy_tail) {
    a <- matrix(0,nrow(d),4,dimnames=list(NULL,c('mu','pi','expected','total_zero')))
    mixsd<-c(1,3)/sqrt(1.8); mixw<-c(.9,.1)
    for(i in 1:2)for(j in 1:2)a<-a+mixw[i]*mixw[j]*integrated(
      ep$count,ep$zi,phi,(c$sd_count*mixsd[i])^2,(c$sd_zi*mixsd[j])^2,nodes=quadrature(max(25,length(nodes$nodes))))
    return(a)
  }
  integrated(ep$count,ep$zi,phi,c$sd_count^2+c$slope_sd^2*d$xw^2+
    if(c$observation_ar).35^2 else 0,c$sd_zi^2,c$rho*c$sd_count*c$sd_zi,
    hurdle=c$hurdle,NB=c$scenario=='NB',count_family=c$count_family,nodes=nodes)
}

contrast_data <- function(c) {
  d <- expand.grid(xw=c(-1,1),context=if(c$context_binary)c(0,1) else c(-1,1),covariate=c(0,1))
  d$mean_x <- 0; d$x_raw<-d$xw; d$exposure<-1; d$off<-0
  # Cross difference: (x+ minus x-) in high versus low context.
  w <- rep(c(1,-1,-1,1),2)*rep(c(.55,.45),each=4)
  list(data=d,weights=w)
}

specifications <- function(c) {
  main <- 'xw + context + mean_x + mean_x:context + covariate'
  re <- '(1|group)'
  spec <- function(cnt=FALSE,zi='add',slope=FALSE,raw=FALSE) {
    mm <- if(raw)'x_raw + context + covariate' else main
    prod <- if(raw)'x_raw:context' else 'xw:context'
    random <- if(slope)'(1|group) + (0+xw|group)' else re
    f <- as.formula(paste('y ~',mm,if(cnt)paste('+',prod) else '', '+ offset(off) +',random))
    z <- switch(zi,none=~0,fixed=~1,random=~1+(1|group),
      fixed_joint=as.formula(paste('~',mm,'+',prod)),
      as.formula(paste('~',mm,if(zi=='cross')paste('+',prod) else '', '+',re)))
    list(count=f,zi=z)
  }
  s <- list(additive=spec(),count=spec(TRUE),inflation=spec(FALSE,'cross'),joint=spec(TRUE,'cross'),
    NB_additive=spec(FALSE,'none'),NB_count=spec(TRUE,'none'),
    ZI_intercept=spec(FALSE,'fixed'),ZI_random_only=spec(FALSE,'random'),
    ZI_fixed_effects_joint=spec(TRUE,'fixed_joint'))
  if(c$slope_sd>0) for(nm in c('additive','count','inflation','joint'))
    s[[paste0('slope_',nm)]] <- spec(nm %in% c('count','joint'),if(nm %in% c('inflation','joint'))'cross' else 'add',TRUE)
  if(c$composition_rho>0) s$undecomposed_joint <- spec(TRUE,'cross',raw=TRUE)
  s
}

audit_fit <- function(m) {
  if(!inherits(m,'glmmTMB')) return(list(valid=FALSE,convergence=NA_integer_,pdHess=FALSE,
    gradient=NA_real_,newton_se=NA_real_,decrement=NA_real_,max_coef=NA_real_,max_se=NA_real_,
    min_RE_sd=NA_real_,logLik=NA_real_,AIC=NA_real_,df=NA_integer_))
  V <- m$sdr$cov.fixed; p <- m$fit$par
  if(is.null(V)||!is.matrix(V)||nrow(V)!=length(p)) {
    out<-audit_fit(NULL);out$convergence<-m$fit$convergence
    return(out)
  }
  g <- tryCatch(m$obj$gr(p),error=function(e) rep(NA,length(p)))
  se <- sqrt(pmax(diag(V),0)); step <- V %*% g
  ns <- max(abs(step)/pmax(se,1e-15)); dec <- sqrt(pmax(0,as.numeric(crossprod(g,step))))
  pd <- isTRUE(m$sdr$pdHess) && all(is.finite(V)) && all(se>0)
  valid <- isTRUE(m$fit$convergence==0)&&pd&&is.finite(ns)&&ns<.01&&is.finite(dec)&&dec<.01
  th<-p[names(p)%in%c('theta','thetazi')]
  list(valid=valid,convergence=m$fit$convergence,pdHess=pd,gradient=max(abs(g)),
    newton_se=ns,decrement=dec,max_coef=max(abs(unlist(fixef(m)))),max_se=max(se),
    min_RE_sd=if(length(th))min(exp(th)) else NA_real_,
    logLik=if(valid)as.numeric(logLik(m)) else NA_real_,
    AIC=if(valid)AIC(m) else NA_real_,df=length(p))
}

fit_one <- function(spec,d) {
  saved <- list(); fits <- list(); audits <- list()
  for(attempt in 1:2) {
    warns <- character(); err <- ''
    ctrl <- if(attempt==1)glmmTMBControl(parallel=1L,optCtrl=list(iter.max=500,eval.max=700,rel.tol=1e-9)) else
      glmmTMBControl(parallel=1L,optimizer=optim,optArgs=list(method='BFGS'),optCtrl=list(maxit=1000,reltol=1e-10))
    elapsed<-system.time(m<-tryCatch(withCallingHandlers(
      glmmTMB(spec$count,ziformula=spec$zi,family=nbinom2(),data=d,control=ctrl),
      warning=function(w){warns<<-c(warns,conditionMessage(w));invokeRestart('muffleWarning')}),
      error=function(e){err<<-conditionMessage(e);NULL}))['elapsed']
    a<-audit_fit(m); fits[attempt]<-list(m); audits[[attempt]]<-a
    saved[[attempt]]<-as.data.frame(c(list(attempt=attempt,optimizer=if(attempt==1)'nlminb' else 'BFGS',
      seconds=as.numeric(elapsed),warnings=paste(unique(warns),collapse=' | '),error=err),a))
    if(a$valid)break
  }
  good<-which(vapply(audits,function(a)isTRUE(a$valid),logical(1)))
  pick<-if(length(good))good[which.max(vapply(audits[good],function(a)a$logLik,numeric(1)))] else length(fits)
  list(model=fits[[pick]],audit=audits[[pick]],attempts=rbindlist(saved),selected_attempt=pick)
}

prediction_engine <- function(m,spec,d) {
  X<-model.matrix(delete.response(terms(lme4::nobars(spec$count))),d)
  Z<-model.matrix(delete.response(terms(lme4::nobars(spec$zi))),d)
  cn<-names(fixef(m)$cond); zn<-names(fixef(m)$zi)
  X<-X[,cn,drop=FALSE]; Z<-Z[,zn,drop=FALSE]
  pn<-names(m$fit$par); iB<-which(pn=='beta'); iZ<-which(pn=='betazi')
  iD<-which(pn=='betadisp'); iT<-which(pn=='theta'); iTZ<-which(pn=='thetazi')
  function(p) {
    vc<-rep(exp(2*p[iT[1]]),nrow(d))
    if(length(iT)>1)vc<-vc+exp(2*p[iT[2]])*d$xw^2
    vz<-if(length(iTZ))exp(2*p[iTZ[1]]) else 0
    integrated(as.numeric(X%*%p[iB])+d$off,if(length(iZ))as.numeric(Z%*%p[iZ]) else rep(0,nrow(d)),
      rep(exp(p[iD[1]]),nrow(d)),vc,vz,NB=length(iZ)==0)
  }
}

wald_test <- function(b,V) {
  if(!length(b)||any(!is.finite(V))||any(!is.finite(b)))return(NA_real_)
  if(min(eigen(V,symmetric=TRUE,only.values=TRUE)$values)<=1e-14)return(NA_real_)
  pchisq(as.numeric(crossprod(b,solve(V,b))),length(b),lower.tail=FALSE)
}

robust_covariances <- function(m,d) {
  warnings<-character()
  st<-system.time(S<-tryCatch(withCallingHandlers(sandwich::estfun(m,full=TRUE,cluster=d$group,rawnames=TRUE),
    warning=function(w){warnings<<-c(warnings,conditionMessage(w));invokeRestart('muffleWarning')}),
    error=function(e){warnings<<-c(warnings,conditionMessage(e));NULL}))['elapsed']
  p<-m$fit$par; C<-m$sdr$cov.fixed; g<-m$obj$gr(p)
  err<-if(is.null(S))Inf else max(abs(colSums(S)+g))
  ordered<-!is.null(S)&&ncol(S)==length(p)&&identical(colnames(S),names(p))
  ok<-ordered&&all(is.finite(S))&&err<.002&&!any(grepl('does not match',warnings,fixed=TRUE))
  audit<-data.frame(valid=ok,parameter_order_match=ordered,score_error=err,seconds=as.numeric(st),warnings=paste(warnings,collapse=' | '))
  if(!ok)return(list(cov=list(),audit=audit))
  J<-nrow(S); meat<-crossprod(S); lag<-max(1L,floor(4*(J/100)^(2/9)))
  hm<-meat
  for(l in seq_len(lag)){a<-crossprod(S[(l+1):J,,drop=FALSE],S[1:(J-l),,drop=FALSE]);hm<-hm+(1-l/(lag+1))*(a+t(a))}
  vc<-C%*%meat%*%C*J/(J-1); vh<-C%*%hm%*%C*J/(J-1)
  list(cov=list(cluster=vc,HAC=vh),audit=transform(audit,HAC_lag=lag))
}

interaction_indices <- function(m,term='xw:context') {
  b<-fixef(m); p<-m$fit$par
  c(count=which(names(p)=='beta')[match(term,names(b$cond))],
    inflation=which(names(p)=='betazi')[match(term,names(b$zi))])
}

classify <- function(global,p_count,p_zi,adjust=TRUE) {
  if(is.na(global))return('failure')
  if(global>=alpha)return('neither')
  if(anyNA(c(p_count,p_zi)))return('failure')
  pp<-if(adjust)p.adjust(c(p_count,p_zi),'holm') else c(p_count,p_zi)
  if(all(pp<alpha))'both' else if(pp[1]<alpha)'count' else if(pp[2]<alpha)'inflation' else 'unlocalized'
}

lrt <- function(a,b) {
  if(!isTRUE(a$audit$valid)||!isTRUE(b$audit$valid))return(c(LR=NA,df=NA,p=NA))
  v<-2*(b$audit$logLik-a$audit$logLik); df<-b$audit$df-a$audit$df
  if(v< -1e-5||df<=0)return(c(LR=NA,df=df,p=NA))
  c(LR=max(v,0),df=df,p=pchisq(max(v,0),df,lower.tail=FALSE))
}

delta_gradient <- function(fn,p) {
  v<-fn(p); G<-matrix(NA_real_,length(v),length(p))
  for(k in seq_along(p)){h<-1e-4*max(1,abs(p[k]));pp<-pm<-p;pp[k]<-pp[k]+h;pm[k]<-pm[k]-h;G[,k]<-(fn(pp)-fn(pm))/(2*h)}
  G
}

run_replication <- function(c,r,save_fits=FALSE,progress=NULL) {
  seed<-as.integer(base_seed+c$condition_id*100000L+r)
  d<-generate_data(c,seed); specs<-specifications(c); fits<-list(); audits<-attempts<-parameters<-predictions<-decisions<-tests<-list()
  ref<-reference_data(c,seed+90000000L); truth<-truth_predictions(c,ref)
  ct<-contrast_data(c); ct_truth<-as.numeric(crossprod(ct$weights,truth_predictions(c,ct$data)))
  names(ct_truth)<-c('mu','pi','expected','total_zero')
  fit_start<-proc.time()[3]
  for(nm in names(specs)) {
    if(!is.null(progress))progress(nm,'fitting',NA)
    f<-fit_one(specs[[nm]],d); fits[[nm]]<-f
    if(!is.null(progress))progress(nm,'fitted',f$audit$valid)
    audits[[nm]]<-as.data.frame(c(list(model=nm,selected_attempt=f$selected_attempt),f$audit))
    attempts[[nm]]<-cbind(model=nm,f$attempts)
    if(!isTRUE(f$audit$valid)) next
    m<-f$model; term<-if(nm=='undecomposed_joint')'x_raw:context' else 'xw:context'
    ii<-interaction_indices(m,term)
    for(comp in names(ii))if(!is.na(ii[comp])) {
      k<-ii[comp]; est<-m$fit$par[k]; se<-sqrt(m$sdr$cov.fixed[k,k])
      tru<-if(comp=='count')c$b_count else c$b_zi
      defined<-!c$hurdle && (comp=='count'||c$scenario!='NB') && nm!='undecomposed_joint'
      parameters[[paste(nm,comp)]]<-data.frame(model=nm,component=comp,method='model',estimate=est,se=se,
        true=if(defined)tru else NA_real_,defined=defined,p=2*pnorm(-abs(est/se)))
    }
    pe<-prediction_engine(m,specs[[nm]],ref); pr<-pe(m$fit$par)
    ce<-prediction_engine(m,specs[[nm]],ct$data); con<-as.numeric(crossprod(ct$weights,ce(m$fit$par)))
    for(k in 1:4){defined<-k>2||!c$hurdle
      predictions[[paste(nm,k)]]<-data.frame(model=nm,metric=colnames(pr)[k],
        mse=if(defined)mean((pr[,k]-truth[,k])^2) else NA_real_,
        contrast=con[k],truth_contrast=if(defined)ct_truth[k] else NA_real_,
        contrast_se=NA_real_,method='model',covered=NA_integer_)
    }
  }
  # Same observation set and random structure for every matched comparison.
  for(prefix in c('',if(c$slope_sd>0)'slope_' else character())) {
    ff<-fits[paste0(prefix,c('additive','count','inflation','joint'))]
    g<-lrt(ff[[1]],ff[[4]]); pc<-lrt(ff[[3]],ff[[4]]); pz<-lrt(ff[[2]],ff[[4]])
    tc<-lrt(ff[[1]],ff[[2]]); tz<-lrt(ff[[1]],ff[[3]])
    for(nm in c('global','conditional_count','conditional_inflation','additive_count','additive_inflation')) {
      vv<-switch(nm,global=g,conditional_count=pc,conditional_inflation=pz,additive_count=tc,additive_inflation=tz)
      tests[[paste(prefix,nm)]]<-data.frame(model=paste0(prefix,'joint'),test=nm,LR=vv[1],df=vv[2],p=vv[3])
    }
    aa<-vapply(ff,function(f)f$audit$AIC,numeric(1))
    aicclass<-if(any(!is.finite(aa)))'failure' else c('neither','count','inflation','both')[which.min(aa)]
    decisions[[paste0(prefix,'gated_LRT')]]<-data.frame(workflow=paste0(prefix,'gated_LRT_Holm'),
      decision=classify(g['p'],pc['p'],pz['p']),selected_model=NA_character_)
    decisions[[paste0(prefix,'gated_LRT_unadjusted')]]<-data.frame(workflow=paste0(prefix,'gated_LRT_unadjusted'),
      decision=classify(g['p'],pc['p'],pz['p'],FALSE),selected_model=NA_character_)
    for(adj in c(TRUE,FALSE)) {
      nam<-paste0(prefix,'conditional_LRT_',if(adj)'Holm' else 'unadjusted')
      u<-classify(0,pc['p'],pz['p'],adj);if(u=='unlocalized')u<-'neither'
      decisions[[nam]]<-data.frame(workflow=nam,decision=u,selected_model=NA_character_)
    }
    decisions[[paste0(prefix,'AIC_four')]]<-data.frame(workflow=paste0(prefix,'AIC_four'),decision=aicclass,
      selected_model=if(aicclass=='failure')NA_character_ else names(ff)[which.min(aa)])
    decisions[[paste0(prefix,'naive_count')]]<-data.frame(workflow=paste0(prefix,'naive_count_only'),
      decision=if(is.na(tc['p']))'failure' else if(tc['p']<alpha)'count' else 'neither',selected_model=NA_character_)
    decisions[[paste0(prefix,'separate')]]<-data.frame(workflow=paste0(prefix,'separate_unadjusted'),
      decision={u<-classify(0,tc['p'],tz['p'],FALSE);if(u=='unlocalized')'neither' else u},selected_model=NA_character_)
  }
  # The no-RE inflation candidates retain all inflation covariates in the
  # joint model; intercept-only/random-only candidates deliberately omit them.
  aa<-vapply(fits,function(f)f$audit$AIC,numeric(1)); usable<-which(is.finite(aa))
  best<-if(length(usable))names(fits)[usable[which.min(aa[usable])]] else NA_character_
  bc<-if(is.na(best))'failure' else if(best %in% c('joint','ZI_fixed_effects_joint','undecomposed_joint','slope_joint'))'both' else
    if(best %in% c('count','NB_count','slope_count'))'count' else if(best %in% c('inflation','slope_inflation'))'inflation' else 'neither'
  decisions$AIC_all<-data.frame(workflow='AIC_all_available',decision=bc,selected_model=best)
  robust_audit<-data.frame(valid=FALSE,score_error=NA_real_,seconds=0,warnings='joint numerical failure',HAC_lag=NA_integer_)
  if(isTRUE(fits$joint$audit$valid)) {
    if(!is.null(progress))progress('joint','scores_and_delta',TRUE)
    m<-fits$joint$model; p<-m$fit$par; ii<-interaction_indices(m)
    rr<-robust_covariances(m,d); robust_audit<-rr$audit
    covs<-c(list(model=m$sdr$cov.fixed),rr$cov)
    ce<-prediction_engine(m,specs$joint,ct$data)
    fun<-function(pp)as.numeric(crossprod(ct$weights,ce(pp)))
    con<-fun(p); G<-delta_gradient(fun,p)
    for(method in names(covs)) {
      V<-covs[[method]]; bb<-p[ii]; vv<-V[ii,ii,drop=FALSE]
      pp<-2*pnorm(-abs(bb/sqrt(diag(vv)))); gp<-wald_test(bb,vv)
      tests[[paste('Wald',method)]]<-data.frame(model='joint',test=paste0('Wald_global_',method),
        LR=if(is.finite(gp))qchisq(gp,2,lower.tail=FALSE) else NA_real_,df=2,p=gp)
      decisions[[paste('Wald',method)]]<-data.frame(workflow=paste0('gated_Wald_',method,'_Holm'),
        decision=classify(gp,pp[1],pp[2]),selected_model=NA_character_)
      for(k in 1:2) {
        comp<-names(ii)[k]; defined<-!c$hurdle&&(comp=='count'||c$scenario!='NB')
        parameters[[paste('joint',comp,method)]]<-data.frame(model='joint',component=comp,method=method,
          estimate=bb[k],se=sqrt(vv[k,k]),true=if(defined)c(if(comp=='count')c$b_count else c$b_zi) else NA_real_,
          defined=defined,p=pp[k])
      }
      cs<-sqrt(pmax(0,diag(G%*%V%*%t(G))))
      joint_pr<-prediction_engine(m,specs$joint,ref)(p)
      for(k in 1:4){defined<-k>2||!c$hurdle
        predictions[[paste('joint',k,method)]]<-data.frame(model='joint',metric=names(ct_truth)[k],
          mse=if(defined)mean((joint_pr[,k]-truth[,k])^2) else NA_real_,
          contrast=con[k],truth_contrast=if(defined)ct_truth[k] else NA_real_,contrast_se=cs[k],method=method,
          covered=if(defined)as.integer(abs(con[k]-ct_truth[k])<=qnorm(.975)*cs[k]) else NA_integer_)
      }
    }
    for(method in setdiff(c('cluster','HAC'),names(rr$cov)))
      decisions[[paste('Wald',method)]]<-data.frame(workflow=paste0('gated_Wald_',method,'_Holm'),decision='failure',selected_model=NA_character_)
    # Remove duplicate original model rows in favour of complete joint inference.
    for(comp in c('count','inflation'))parameters[[paste('joint',comp)]]<-NULL
    for(k in 1:4)predictions[[paste('joint',k)]]<-NULL
  } else for(method in c('model','cluster','HAC'))
    decisions[[paste('Wald',method)]]<-data.frame(workflow=paste0('gated_Wald_',method,'_Holm'),decision='failure',selected_model=NA_character_)
  dec<-rbindlist(decisions,fill=TRUE)
  for(i in which(is.na(dec$selected_model)&dec$decision!='failure')) {
    prefix<-if(startsWith(dec$workflow[i],'slope_'))'slope_' else ''
    nm<-switch(dec$decision[i],neither='additive',count='count',inflation='inflation',both='joint',unlocalized='joint')
    dec$selected_model[i]<-paste0(prefix,nm)
  }
  par<-rbindlist(parameters,fill=TRUE); pred<-rbindlist(predictions,fill=TRUE)
  if(nrow(pred))pred[,prediction_valid:=is.finite(mse)&is.finite(contrast)]
  out<-list(condition_id=c$condition_id,replication=r,seed=seed,version=simulation_version,
    data_audit=attr(d,'audit'),fits=rbindlist(audits,fill=TRUE),attempts=rbindlist(attempts,fill=TRUE),
    parameters=par,predictions=pred,
    decisions=dec,tests=rbindlist(tests,fill=TRUE),robust=robust_audit,
    elapsed=proc.time()[3]-fit_start)
  if(save_fits)out$retained<-list(data=d,models=lapply(fits,`[[`,'model'),specs=specs,reference=ref,truth=truth)
  out
}

atomic_rds <- function(x,path) {
  dir.create(dirname(path),recursive=TRUE,showWarnings=FALSE)
  tmp<-paste0(path,'.',Sys.getpid(),'.tmp'); saveRDS(x,tmp,compress=TRUE)
  if(!file.rename(tmp,path))stop('Atomic checkpoint rename failed: ',path)
}

execute_task <- function(task) {
  c<-as.list(task$condition); r<-task$replication; path<-task$path
  if(file.exists(path)) {
    old<-readRDS(path)
    if(old$version!=simulation_version||old$condition_id!=c$condition_id||old$replication!=r)stop('Checkpoint mismatch')
    return(data.frame(condition_id=c$condition_id,replication=r,status='resumed',seconds=old$elapsed))
  }
  pdir<-file.path(dirname(dirname(path)),'task_progress');dir.create(pdir,showWarnings=FALSE)
  progress<-function(model,stage,valid){
    jsonlite::write_json(list(pid=Sys.getpid(),condition_id=c$condition_id,replication=r,
      model=model,stage=stage,valid=valid,updated=as.character(Sys.time())),
      file.path(pdir,paste0('worker_',Sys.getpid(),'.json')),auto_unbox=TRUE,pretty=TRUE,na='null')
  }
  x<-tryCatch(run_replication(c,r,save_fits=r==1,progress=progress),error=function(e)
    list(condition_id=c$condition_id,replication=r,seed=as.integer(base_seed+c$condition_id*100000L+r),
      version=simulation_version,pipeline_error=conditionMessage(e),elapsed=NA_real_))
  atomic_rds(x,path)
  progress('all','checkpointed',is.null(x$pipeline_error))
  data.frame(condition_id=c$condition_id,replication=r,
    status=if(is.null(x$pipeline_error))'completed' else 'pipeline_error',seconds=x$elapsed)
}

if(sys.nframe()==0) {
  stop('Source simulation.R from run.R; do not execute it directly.')
}
