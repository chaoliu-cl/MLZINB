# Independent numerical and design checks; retains a single benchmark replicate.
arg<-function(key,default){v<-grep(paste0('^--',key,'='),commandArgs(TRUE),value=TRUE);if(length(v))sub(paste0('^--',key,'='),'',v[1]) else default}
script<-sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
root<-dirname(normalizePath(script,winslash='/'))
source(file.path(root,'simulation.R'));source(file.path(root,'summarize.R'))
data.table::setDTthreads(1)
checks<-list()
check<-function(name,ok,detail=''){
  checks[[length(checks)+1L]]<<-data.frame(check=name,passed=isTRUE(ok),detail=as.character(detail))
  cat(if(isTRUE(ok))'PASS' else 'FAIL',name,as.character(detail),'\n')
}
grid<-condition_grid();check('core_and_stress_grid',nrow(grid[suite=='core'])==22L&&nrow(grid)==58L,nrow(grid))
seed_range<-range(base_seed+grid$condition_id*100000+100000L)
check('noncolliding_seed_blocks',!anyDuplicated(grid$condition_id)&&max(seed_range)<.Machine$integer.max,
  'condition seed blocks disjoint for reps 1..100000; independent reference offset exceeds all blocks')
for(id in grid$condition_id) {
  cc<-as.list(grid[condition_id==id]);d<-generate_data(cc,base_seed+id*100000L+1L)
  a<-attr(d,'audit')
  ok<-all(is.finite(d$y))&&all(d$y>=0)&&all(d$y==floor(d$y))&&
    nlevels(d$group)==cc$J&&a$within_mean_error<1e-12&&
    all(tapply(d$context,d$group,function(x)length(unique(x)))==1)
  check(paste0('DGP_',id),ok,paste(nrow(d),'rows;',a$context_support,'context levels'))
  tr<-truth_predictions(cc,reference_data(cc,1000000L+id))
  check(paste0('truth_finite_',id),all(is.finite(tr))&&all(tr[,'pi']>=0&tr[,'pi']<=1)&&
    all(tr[,'total_zero']>=0&tr[,'total_zero']<=1))
}
# Probability identities at zero variance have a direct closed form.
eta<-c(-2,0,1,3);zeta<-c(-3,-.5,1,2);phi<-1.4
a<-integrated(eta,zeta,phi,0,0);mu<-exp(eta);pi<-plogis(zeta);p0<-dnbinom(0,mu=mu,size=phi)
exact<-cbind(mu,pi,(1-pi)*mu,pi+(1-pi)*p0)
check('zero_RE_mixture_identity',max(abs(a-exact))<1e-12,max(abs(a-exact)))
qerr<-0
for(id in grid$condition_id) {
  cc<-as.list(grid[condition_id==id]);dd<-contrast_data(cc)$data;ep<-linear_predictors(cc,dd)
  a<-integrated(ep$count,ep$zi,cc$phi,cc$sd_count^2+cc$slope_sd^2*dd$xw^2,cc$sd_zi^2,
    cc$rho*cc$sd_count*cc$sd_zi,hurdle=cc$hurdle,NB=cc$scenario=='NB',count_family=cc$count_family)
  b<-integrated(ep$count,ep$zi,cc$phi,cc$sd_count^2+cc$slope_sd^2*dd$xw^2,cc$sd_zi^2,
    cc$rho*cc$sd_count*cc$sd_zi,hurdle=cc$hurdle,NB=cc$scenario=='NB',count_family=cc$count_family,nodes=quadrature(41))
  qerr<-max(qerr,max(abs(a-b)/pmax(1,abs(b))))
}
check('quadrature_13_vs_41',qerr<1e-4,qerr)
cc<-as.list(grid[heavy_tail==TRUE]);dd<-contrast_data(cc)$data
qmix<-max(abs(truth_predictions(cc,dd)-truth_predictions(cc,dd,nodes=quadrature(41))))
check('finite_moment_heavy_tail_quadrature',qmix<1e-5,qmix)
# Deliberately degenerate binary support remains explicit and finite, not redrawn.
cc<-as.list(grid[label=='imbalanced_binary']);cc$context_probability<-1e-9
dd<-generate_data(cc,12345)
check('one_level_context_no_resampling',attr(dd,'audit')$context_support==1L&&all(is.finite(dd$mean_x)))
check('component_classification',
  classify(.01,.001,.4)=='count'&&classify(.01,.4,.001)=='inflation'&&
  classify(.01,.001,.002)=='both'&&classify(.01,.04,.04)=='unlocalized'&&
  classify(.2,NA,NA)=='neither'&&classify(.01,NA,.01)=='failure')
rr<-rate_stats(rep(FALSE,500));check('zero_event_MC_interval',rr$mc_low>=-1e-15&&rr$mc_high>0&&rr$mcse==0,rr$mc_high)
if(arg('fit','true')=='true') {
  cc<-as.list(grid[label=='opposite_e0.30_J40_n30'])
  cached<-FALSE
  if(arg('cached-benchmark','false')=='true') {
    ph<-file.path(root,'verification','source_hashes.rds')
    if(!file.exists(ph)||readRDS(ph)[['simulation.R']]!=unname(tools::md5sum(file.path(root,'simulation.R'))))
      stop('Cached benchmark does not match current simulation source')
    x<-readRDS(file.path(root,'verification','benchmark.rds'));cached<-TRUE
  }
  if(!cached)x<-run_replication(cc,1,save_fits=TRUE)
  dir.create(file.path(root,'verification'),showWarnings=FALSE)
  saveRDS(x,file.path(root,'verification','benchmark.rds'))
  m<-x$retained$models$joint;dd<-x$retained$data;spec<-x$retained$specs$joint
  check('benchmark_joint_numerical',x$fits[model=='joint']$valid,x$elapsed)
  check('full_cluster_score_identity',x$robust$valid&&x$robust$score_error<.002,x$robust$score_error)
  check('likelihood_comparisons_same_sample',all(vapply(x$retained$models,nobs,numeric(1))==nrow(dd))&&
    all(x$tests[test%in%c('global','conditional_count','conditional_inflation')]$df==c(2,1,1)))
  # Set marginal variances approximately to zero and compare with glmmTMB's
  # fixed-effects predictions: tests design-column ordering, offsets, and links.
  p<-m$fit$par;p[names(p)%in%c('theta','thetazi')]<- -30
  nd<-x$retained$reference;nd$group<-factor(rep('independent_new_group',nrow(nd)))
  nd$off<-seq(-.6,.6,length.out=nrow(nd))
  pe<-prediction_engine(m,spec,nd);pr<-pe(p)
  # New levels also ensure inflation BLUPs are zero: the installed package's
  # re.form=NA path can retain inflation BLUPs for previously observed groups.
  pm<-predict(m,newdata=nd,type='conditional',re.form=NA,allow.new.levels=TRUE)
  pz<-predict(m,newdata=nd,type='zprob',re.form=NA,allow.new.levels=TRUE)
  check('prediction_engine_vs_package_new_groups',max(abs(pr[,'mu']-pm))<1e-8&&max(abs(pr[,'pi']-pz))<1e-8,
    max(abs(pr[,'pi']-pz)))
  ct<-contrast_data(cc);fn<-function(pp)as.numeric(crossprod(ct$weights,prediction_engine(m,spec,ct$data)(pp)))
  G<-delta_gradient(fn,m$fit$par)
  G2<-numDeriv::jacobian(fn,m$fit$par,method='Richardson')
  check('delta_gradient_independent',max(abs(G-G2)/pmax(1,abs(G2)))<1e-5,max(abs(G-G2)))
  # Count slope theta order checked against the package's random-effect structure.
  cs<-as.list(grid[label=='random_slope_dual']);ss<-specifications(cs)$slope_joint
  fm<-fit_one(ss,dd);sm<-fm$model
  check('random_slope_model_numerical',fm$audit$valid)
  if(fm$audit$valid) {
    th<-sm$fit$par[names(sm$fit$par)=='theta'];vc<-VarCorr(sm)$cond
    check('random_slope_theta_order',length(th)==2L&&
      abs(exp(th[1])-attr(vc[[1]],'stddev')[1])<1e-12&&
      abs(exp(th[2])-attr(vc[[2]],'stddev')[1])<1e-12)
    sp<-prediction_engine(sm,ss,ct$data)(sm$fit$par)
    check('random_slope_prediction_finite',all(is.finite(sp)))
  }
  # Check exact repeatability of DGP and deterministic out-of-sample reference.
  d2<-generate_data(cc,x$seed);check('DGP_repeatability',identical(dd,d2))
  check('reference_independent',!identical(x$retained$reference$xw,head(dd$xw,96)))
  # Resumption returns the checkpoint without refitting or changing bytes.
  path<-file.path(root,'verification','resume_test.rds');atomic_rds(x,path)
  h1<-tools::md5sum(path)
  res<-execute_task(list(condition=cc,replication=1,path=path))
  check('checkpoint_resume_unchanged',res$status=='resumed'&&identical(h1,tools::md5sum(path)))
  unlink(path)
  stub<-file.path(root,'verification','report_check');dir.create(stub,showWarnings=FALSE)
  atomic_rds(list(version=simulation_version,base_seed=base_seed,mode='smoke',reps=1L),file.path(stub,'configuration.rds'))
  fwrite(grid[condition_id==cc$condition_id],file.path(stub,'condition_grid.csv'))
  atomic_rds(x,file.path(stub,'checkpoints',sprintf('c%03d_r000001.rds',cc$condition_id)))
  s<-summarize_run(stub,make_plots=TRUE)
  t<-fread(file.path(stub,'tables','parameter_recovery.csv'))
  check('report_pipeline_and_denominators',s$complete&&s$pipeline_errors==0&&all(t$completed_reps==1)&&all(t$planned_reps==1))
  check('report_four_prediction_targets',fread(file.path(stub,'tables','independent_prediction_mse.csv'))[,uniqueN(metric)]==4)
}
dir.create(file.path(root,'verification'),showWarnings=FALSE)
tab<-rbindlist(checks);fwrite(tab,file.path(root,'verification','checks.csv'))
writeLines(capture.output(sessionInfo()),file.path(root,'verification','sessionInfo.txt'))
if(any(!tab$passed))stop('Verification checks failed; see verification/checks.csv')
if(arg('fit','true')=='true') {
  hf<-tools::md5sum(file.path(root,c('simulation.R','run.R','summarize.R','verify.R','PROTOCOL.md')))
  names(hf)<-basename(names(hf));saveRDS(hf,file.path(root,'verification','source_hashes.rds'))
}
cat(sprintf('All %d verification checks passed.\n',nrow(tab)))
