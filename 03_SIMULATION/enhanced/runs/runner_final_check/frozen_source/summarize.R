# Aggregate verified checkpoints. All tables retain completed/planned denominators.
# Can also run directly: Rscript summarize.R --run=<absolute-or-relative-run-dir>
suppressPackageStartupMessages(library(data.table))
rate_stats<-function(x) {
  x<-x[!is.na(x)];n<-length(x)
  if(!n)return(list(n=0L,rate=NA_real_,mcse=NA_real_,mc_low=NA_real_,mc_high=NA_real_))
  p<-mean(x);z<-qnorm(.975);den<-1+z^2/n
  ctr<-(p+z^2/(2*n))/den;half<-z*sqrt(p*(1-p)/n+z^2/(4*n^2))/den
  list(n=n,rate=p,mcse=sqrt(p*(1-p)/n),mc_low=ctr-half,mc_high=ctr+half)
}
mean_stats<-function(x) {
  x<-x[is.finite(x)];n<-length(x)
  list(n=n,mean=if(n)mean(x) else NA_real_,mcse=if(n>1)sd(x)/sqrt(n) else NA_real_)
}
summarize_run<-function(output,make_plots=TRUE) {
  output<-normalizePath(output,winslash='/')
  cfg<-readRDS(file.path(output,'configuration.rds'));grid<-fread(file.path(output,'condition_grid.csv'))
  scenarios<-c(null='Null focal moderation',additive='Additive context',NB='NB truth',
    inflation='Inflation only',count='Count only',same='Dual same signs',opposite='Dual opposite signs')
  grid[,plot_label:=ifelse(suite=='core',paste0(scenarios[scenario],
    ifelse(effect>0,paste0(' (',sprintf('%.2f',effect),')'),''),'; ',J,' x ',n),gsub('_',' ',label))]
  files<-list.files(file.path(output,'checkpoints'),pattern='^c[0-9]+_r[0-9]+[.]rds$',full.names=TRUE)
  if(!length(files))stop('No checkpoints to aggregate')
  keys<-c('data_audit','fits','attempts','parameters','predictions','decisions','tests','robust')
  raw<-setNames(lapply(keys,function(k)vector('list',length(files))),keys)
  manifest<-vector('list',length(files))
  for(i in seq_along(files)) {
    x<-readRDS(files[i]);id<-x$condition_id;r<-x$replication
    if(x$version!=cfg$version||!id%in%grid$condition_id||r<1||r>cfg$reps||
       x$seed!=cfg$base_seed+id*100000+r||basename(files[i])!=sprintf('c%03d_r%06d.rds',id,r))
      stop('Checkpoint identity/seed/version mismatch: ',files[i])
    manifest[[i]]<-data.table(condition_id=id,replication=r,seed=x$seed,
      pipeline_error=if(is.null(x$pipeline_error))'' else x$pipeline_error,elapsed=x$elapsed)
    for(k in keys)if(!is.null(x[[k]])&&nrow(x[[k]]))raw[[k]][[i]]<-cbind(condition_id=id,replication=r,as.data.table(x[[k]]))
    # Retained fitted objects are intentionally not accumulated in memory.
    rm(x)
  }
  manifest<-rbindlist(manifest);stopifnot(!anyDuplicated(manifest[,.(condition_id,replication)]))
  raw<-lapply(raw,rbindlist,fill=TRUE)
  dest<-file.path(output,'tables');dir.create(dest,showWarnings=FALSE)
  rawdir<-file.path(output,'raw');dir.create(rawdir,showWarnings=FALSE)
  fwrite(manifest,file.path(dest,'checkpoint_manifest.csv'))
  counts<-manifest[,.(completed_reps=.N,pipeline_errors=sum(nzchar(pipeline_error))),by=condition_id]
  counts<-merge(grid[,.(condition_id,label,suite,scenario,truth_class,estimand_status,misspecified)],counts,all.x=TRUE)
  counts[is.na(completed_reps),`:=`(completed_reps=0L,pipeline_errors=0L)]
  counts[,`:=`(planned_reps=cfg$reps,remaining_reps=cfg$reps-completed_reps)]
  complete<-all(counts$remaining_reps==0L)&&!any(nzchar(manifest$pipeline_error))
  fwrite(counts,file.path(dest,'completion_by_condition.csv'))
  for(k in keys)if(nrow(raw[[k]]))fwrite(raw[[k]],file.path(rawdir,paste0(k,'.csv.gz')))
  decorate<-function(d)merge(d,counts,by='condition_id',all.x=TRUE)
  write_table<-function(d,nm){fwrite(decorate(d),file.path(dest,paste0(nm,'.csv')));invisible(d)}
  # Failed pipeline checkpoints are explicit failures for every intended workflow.
  dec<-raw$decisions
  for(i in which(nzchar(manifest$pipeline_error))) {
    row<-manifest[i];cc<-grid[condition_id==row$condition_id]
    w<-c('gated_LRT_Holm','gated_LRT_unadjusted','conditional_LRT_Holm','conditional_LRT_unadjusted',
      'AIC_four','naive_count_only','separate_unadjusted','AIC_all_available',
      'gated_Wald_model_Holm','gated_Wald_cluster_Holm','gated_Wald_HAC_Holm')
    if(cc$slope_sd>0)w<-c(w,paste0('slope_',c('gated_LRT_Holm','gated_LRT_unadjusted',
      'conditional_LRT_Holm','conditional_LRT_unadjusted','AIC_four','naive_count_only','separate_unadjusted')))
    dec<-rbind(dec,data.table(condition_id=row$condition_id,replication=row$replication,
      workflow=w,decision='failure',selected_model=NA_character_),fill=TRUE)
  }
  expected_decisions<-sum(vapply(grid$condition_id,function(id)
    sum(manifest$condition_id==id)*(11+7*(grid[condition_id==id]$slope_sd>0)),numeric(1)))
  stopifnot(nrow(dec)==expected_decisions,!anyDuplicated(dec[,.(condition_id,replication,workflow)]))
  if(nrow(dec)) {
    dec<-merge(dec,grid[,.(condition_id,truth_class,b_count,b_zi,scenario)],by='condition_id')
    dec[,`:=`(valid=decision!='failure',declared_count=decision%in%c('count','both'),
      declared_inflation=decision%in%c('inflation','both'))]
    dec[,`:=`(detected=decision%in%c('count','inflation','both','unlocalized'),
      exact=decision==truth_class,unlocalized=decision=='unlocalized',
      false_count=declared_count&b_count==0,false_inflation=declared_inflation&b_zi==0,
      false_any=(declared_count&b_count==0)|(declared_inflation&b_zi==0),
      missed_active=(b_count!=0&!declared_count)|(b_zi!=0&!declared_inflation))]
    # A hurdle product is not a true ML-ZINB component product. Keep operational
    # discovery frequencies, but do not label them correct/incorrect localization.
    dec[truth_class=='undefined_hurdle',c('exact','false_count','false_inflation','false_any','missed_active'):=
      list(NA,NA,NA,NA,NA)]
    decision_summary<-dec[,{
      rbindlist(lapply(c('valid','detected','exact','unlocalized','declared_count','declared_inflation',
        'false_count','false_inflation','false_any','missed_active'),function(ev){
        rbind(cbind(event=ev,denominator='completed_including_failures',as.data.table(rate_stats(get(ev)))),
          cbind(event=ev,denominator='valid_workflow',as.data.table(rate_stats(get(ev)[valid]))))}))
    },by=.(condition_id,workflow)]
    write_table(decision_summary,'workflow_operating_characteristics')
    # Counts include failure and global-only/unlocalized categories.
    confusion<-dec[,.N,by=.(condition_id,workflow,decision)]
    confusion[,rate_among_completed:=N/sum(N),by=.(condition_id,workflow)]
    write_table(confusion,'classification_confusion')
    fwrite(dec,file.path(rawdir,'decisions_with_truth.csv.gz'))
    primary<-dec[workflow=='gated_LRT_Holm',.(condition_id,replication,valid,exact,detected,false_any)]
    paired<-merge(dec,primary,by=c('condition_id','replication'),suffixes=c('','_primary'))
    paired<-paired[workflow!='gated_LRT_Holm']
    ps<-paired[,rbindlist(lapply(c('exact','detected','false_any'),function(ev){
      dif<-as.numeric(get(ev))-as.numeric(get(paste0(ev,'_primary')))
      rbind(cbind(event=ev,denominator='all_completed',as.data.table(mean_stats(dif))),
        cbind(event=ev,denominator='both_workflows_valid',as.data.table(mean_stats(dif[valid&valid_primary]))))
    })),by=.(condition_id,workflow)]
    write_table(ps,'paired_workflow_differences_vs_primary')
  }
  fits<-raw$fits
  if(nrow(raw$tests)) {
    tt<-merge(raw$tests,counts[,.(condition_id,completed_reps)],by='condition_id')
    ts<-tt[,{v<-is.finite(p);cr<-rate_stats(p[v]<.05)
      all_events<-c(p[v]<.05,rep(FALSE,completed_reps[1]-sum(v)))
      ar<-rate_stats(all_events)
      list(valid_tests=sum(v),valid_test_fraction=sum(v)/completed_reps[1],
        rejection_given_valid=cr$rate,rejection_mcse=cr$mcse,rejection_mc_low=cr$mc_low,rejection_mc_high=cr$mc_high,
        rejection_per_completed=ar$rate,operational_mcse=ar$mcse,
        operational_mc_low=ar$mc_low,operational_mc_high=ar$mc_high)
    },by=.(condition_id,model,test)]
    write_table(ts,'test_operating_characteristics')
  }
  if(nrow(fits)) {
    fs<-fits[,{r<-rate_stats(!valid);list(attempted=.N,valid_fits=sum(valid),
      failure_rate=r$rate,failure_mcse=r$mcse,failure_mc_low=r$mc_low,failure_mc_high=r$mc_high,
      retry_fraction=mean(selected_attempt>1),boundary_sd_fraction=mean(min_RE_sd<.001,na.rm=TRUE),
      median_newton_se=median(newton_se,na.rm=TRUE),
      max_newton_se=if(any(is.finite(newton_se)))max(newton_se[is.finite(newton_se)]) else NA_real_)},by=.(condition_id,model)]
    write_table(fs,'numerical_reliability')
  }
  pars<-raw$parameters
  if(nrow(pars)) {
    stopifnot(!anyDuplicated(pars[,.(condition_id,replication,model,component,method)]))
    # NB inflation and hurdle component recovery are undefined, never assigned zero bias.
    pars[,usable:=defined&is.finite(estimate)&is.finite(se)&se>0&is.finite(true)]
    pars[,`:=`(error=estimate-true,coverage=abs(estimate-true)<=qnorm(.975)*se,
      reject=p<.05,wrong_sign=estimate*true<0)]
    pt<-pars[usable==TRUE,{
      cr<-rate_stats(coverage);rr<-rate_stats(reject);sr<-rate_stats(wrong_sign)
      sq<-error^2;rmse<-sqrt(mean(sq));esd<-sd(estimate)
      list(n=.N,true=true[1],bias=mean(error),bias_mcse=sd(error)/sqrt(.N),
        rmse=rmse,rmse_mcse=if(.N>1&&rmse>0)sd(sq)/sqrt(.N)/(2*rmse) else NA_real_,
        empirical_sd=esd,mean_model_se=mean(se),se_ratio=mean(se)/esd,
        coverage=cr$rate,coverage_mcse=cr$mcse,coverage_mc_low=cr$mc_low,coverage_mc_high=cr$mc_high,
        rejection=rr$rate,rejection_mcse=rr$mcse,rejection_mc_low=rr$mc_low,rejection_mc_high=rr$mc_high,
        wrong_sign=sr$rate,wrong_sign_mcse=sr$mcse)
    },by=.(condition_id,model,component,method)]
    write_table(pt,'parameter_recovery')
    undef<-pars[defined==FALSE,.(n=.N,median_abs_estimate=median(abs(estimate)),median_se=median(se),
      nominal_rejection_fraction=mean(p<.05)),by=.(condition_id,model,component,method)]
    if(nrow(undef))write_table(undef,'undefined_component_diagnostics')
  }
  pred<-raw$predictions
  if(nrow(pred)) {
    stopifnot(!anyDuplicated(pred[,.(condition_id,replication,model,metric,method)]))
    pp<-pred[is.finite(mse),as.data.table(mean_stats(mse)),by=.(condition_id,model,metric,method)]
    write_table(pp,'independent_prediction_mse')
    pred[,error:=contrast-truth_contrast]
    cp<-pred[is.finite(error),{
      cv<-rate_stats(covered);sq<-error^2;rm<-sqrt(mean(sq))
      list(n=.N,truth=truth_contrast[1],bias=mean(error),bias_mcse=sd(error)/sqrt(.N),rmse=rm,
        rmse_mcse=if(.N>1&&rm>0)sd(sq)/sqrt(.N)/(2*rm) else NA_real_,
        empirical_sd=sd(contrast),mean_se=if(any(is.finite(contrast_se)))mean(contrast_se,na.rm=TRUE) else NA_real_,
        interval_n=cv$n,coverage=cv$rate,coverage_mcse=cv$mcse,coverage_mc_low=cv$mc_low,coverage_mc_high=cv$mc_high)
    },by=.(condition_id,model,metric,method)]
    write_table(cp,'response_contrast_recovery')
    # Compare prediction after each decision rule. The unlocalized rule retains joint.
    # These are prediction risks, not post-selection confidence intervals.
    chosen<-merge(dec[,.(condition_id,replication,workflow,selected_model,decision)],
      pred[method=='model',.(condition_id,replication,model,metric,mse)],
      by.x=c('condition_id','replication','selected_model'),by.y=c('condition_id','replication','model'),all.x=TRUE,allow.cartesian=TRUE)
    selected<-chosen[is.finite(mse),as.data.table(mean_stats(mse)),by=.(condition_id,workflow,metric)]
    if(nrow(selected))write_table(selected,'workflow_selected_prediction_mse')
    joint<-pred[model=='joint'&method=='model',.(condition_id,replication,metric,joint_mse=mse)]
    compare<-merge(chosen,joint,by=c('condition_id','replication','metric'))
    paired_pred<-compare[is.finite(mse)&is.finite(joint_mse),as.data.table(mean_stats(mse-joint_mse)),by=.(condition_id,workflow,metric)]
    if(nrow(paired_pred))write_table(paired_pred,'paired_selected_prediction_differences_vs_joint')
    # Paired candidate differences isolate the cost of omitting either component.
    cand<-merge(pred[method=='model'],joint,by=c('condition_id','replication','metric'))
    pd<-cand[is.finite(mse)&is.finite(joint_mse),as.data.table(mean_stats(mse-joint_mse)),by=.(condition_id,model,metric)]
    write_table(pd,'paired_candidate_prediction_differences_vs_joint')
  }
  if(nrow(raw$data_audit)) {
    dd<-raw$data_audit[,lapply(.SD,mean,na.rm=TRUE),by=condition_id,.SDcols=setdiff(names(raw$data_audit),c('condition_id','replication'))]
    write_table(dd,'realized_data_characteristics')
  }
  if(nrow(raw$robust)) {
    rt<-raw$robust[,as.data.table(rate_stats(valid)),by=condition_id]
    write_table(rt,'robust_score_success')
  }
  figdir<-file.path(output,'figures');dir.create(figdir,showWarnings=FALSE)
  if(make_plots&&nrow(dec)) {
    suppressPackageStartupMessages(library(ggplot2))
    watermark<-if(complete&&cfg$mode=='full')'Production simulation' else 'PARTIAL / EXECUTION CHECK - not final Monte Carlo evidence'
    theme_set(theme_bw(base_size=11)+theme(plot.caption=element_text(colour='firebrick'),legend.position='bottom'))
    save_plot<-function(p,name,w=10,h=7){ggsave(file.path(figdir,paste0(name,'.png')),p,width=w,height=h,dpi=180);
      ggsave(file.path(figdir,paste0(name,'.pdf')),p,width=w,height=h)}
    core_ids<-grid[suite=='core']$condition_id
    if(length(core_ids)) {
    cd<-merge(confusion[workflow=='gated_LRT_Holm'&condition_id%in%core_ids],grid[,.(condition_id,plot_label)],by='condition_id')
    p<-ggplot(cd,aes(decision,factor(plot_label,levels=rev(grid[suite=='core']$plot_label)),fill=rate_among_completed))+
      geom_tile()+geom_text(aes(label=sprintf('%.2f',rate_among_completed)),size=2.5)+
      scale_fill_viridis_c(limits=c(0,1))+labs(x='Decision',y=NULL,fill='Rate',title='Primary workflow: localization and numerical failure',caption=watermark)
    save_plot(p,'core_localization',10,8)
    op<-decorate(decision_summary[workflow%in%c('gated_LRT_Holm','separate_unadjusted','naive_count_only','AIC_four')&
      denominator=='completed_including_failures'&event%in%c('detected','exact','false_any')&condition_id%in%core_ids])
    op<-merge(op,grid[,.(condition_id,plot_label)],by='condition_id')
    p<-ggplot(op,aes(rate,factor(plot_label,levels=rev(grid[suite=='core']$plot_label)),colour=workflow))+
      geom_errorbar(aes(xmin=mc_low,xmax=mc_high),width=.25,position=position_dodge(width=.6),orientation='y')+
      geom_point(position=position_dodge(width=.6),size=1.3)+facet_wrap(~event,nrow=1)+
      scale_x_continuous(limits=c(0,1))+labs(x='Rate and 95% Monte Carlo interval',y=NULL,colour='Workflow',caption=watermark)
    save_plot(p,'core_workflow_comparison',14,10)
    }
    if(exists('pt')&&nrow(pt)) {
      cc<-merge(decorate(pt[model=='joint']),grid[,.(condition_id,plot_label)],by='condition_id')
      p<-ggplot(cc,aes(coverage,factor(plot_label,levels=rev(grid$plot_label)),colour=method))+
        geom_vline(xintercept=.95,linetype=2)+geom_point(position=position_dodge(width=.5),size=1)+
        facet_wrap(~component)+scale_x_continuous(limits=c(0,1))+
        labs(x='95% interval coverage, conditional on usable fits',y=NULL,colour='Covariance',caption=watermark)
      save_plot(p,'joint_interval_coverage',11,14)
    }
    if(exists('pp')&&nrow(pp)&&length(core_ids)) {
      ep<-merge(decorate(pp[method=='model'&model%in%c('additive','count','inflation','joint')&condition_id%in%core_ids]),grid[,.(condition_id,plot_label)],by='condition_id')
      p<-ggplot(ep,aes(model,factor(plot_label,levels=rev(grid[suite=='core']$plot_label)),fill=log10(pmax(mean,1e-12))))+
        geom_tile()+facet_wrap(~metric,scales='free_x')+scale_fill_viridis_c()+
        labs(x='Fitted model',y=NULL,fill='log10 MSE',title='Independent new-cluster prediction: four distinct targets',caption=watermark)
      save_plot(p,'component_prediction_errors',12,12)
    }
    if(exists('fs')&&nrow(fs)) {
      ff<-merge(decorate(fs),grid[,.(condition_id,plot_label)],by='condition_id')
      p<-ggplot(ff,aes(model,factor(plot_label,levels=rev(grid$plot_label)),fill=failure_rate))+
        geom_tile()+scale_fill_viridis_c(limits=c(0,1))+theme(axis.text.x=element_text(angle=60,hjust=1))+
        labs(x=NULL,y=NULL,fill='Failure rate',title='Numerical reliability of every candidate',caption=watermark)
      save_plot(p,'numerical_failures',13,15)
    }
    if(exists('pd')&&nrow(pd)&&length(core_ids)) {
      cost<-decorate(pd[model%in%c('additive','count','inflation')&condition_id%in%core_ids])
      cost<-merge(cost,grid[,.(condition_id,plot_label)],by='condition_id')
      cost<-merge(cost,pp[model=='joint'&method=='model',.(condition_id,metric,joint_risk=mean)],by=c('condition_id','metric'))
      cost[,relative_increase:=mean/pmax(joint_risk,1e-12)]
      p<-ggplot(cost,aes(model,factor(plot_label,levels=rev(grid[suite=='core']$plot_label)),fill=relative_increase))+
        geom_tile()+facet_wrap(~metric,scales='free')+scale_fill_gradient2(low='#2166ac',mid='white',high='#b2182b')+
        labs(x='Reduced model',y=NULL,fill='Relative MSE increase',title='Paired omission cost relative to joint model',caption=watermark)
      save_plot(p,'paired_component_omission_cost',12,12)
    }
    design_ids<-grid[label%in%c('opposite_e0.15_J40_n30','opposite_e0.15_J80_n60',
      'more_units_same_clusters','more_clusters_same_units','many_clusters')]$condition_id
    design<-merge(decision_summary[condition_id%in%design_ids&workflow=='gated_LRT_Holm'&
      denominator=='completed_including_failures'&event%in%c('detected','exact')],grid[,.(condition_id,J,units=n)],by='condition_id')
    if(nrow(design)) {
      p<-ggplot(design,aes(J,rate,colour=factor(units),group=units))+
        geom_line()+geom_point()+geom_errorbar(aes(ymin=mc_low,ymax=mc_high),width=3)+
        facet_wrap(~event)+scale_y_continuous(limits=c(0,1))+
        labs(x='Number of clusters',y='Rate and 95% Monte Carlo interval',colour='Units per cluster',
          title='Cluster number versus cluster size: opposite effects of 0.15',caption=watermark)
      save_plot(p,'cluster_number_vs_size',10,5)
    }
  }
  state<-if(complete)'All planned checkpoints completed without pipeline errors.' else 'PARTIAL: pending checkpoints or pipeline errors remain.'
  note<-c('# Enhanced ML-ZINB simulation results', '',paste('Status:',state),
    sprintf('Mode: %s. %d/%d paired datasets checkpointed across %d conditions; %d pipeline errors.',
      cfg$mode,nrow(manifest),nrow(grid)*cfg$reps,nrow(grid),sum(nzchar(manifest$pipeline_error))),
    '',if(cfg$mode!='full'||!complete)'**These are execution/provisional results, not final publication evidence.**' else
      'Assess the Monte Carlo intervals and numerical failure rates before using results in the manuscript.',
    '', 'The original pilot is preserved. Candidates share each generated dataset and all comparisons are paired.',
    'Inference uses accepted fits only. Completed-denominator workflow rates count failures as no discovery; valid-workflow rates exclude them. Pending datasets are not silently treated as failures.',
    'Under NB truth, inflation claims are operational overclaims, not a regular identifiable-parameter type-I error. Under hurdle truth, only observable mean/zero targets and operational discovery frequencies are compared; component-localization accuracy is undefined.',
    'Response-scale cross differences can be nonzero without a link-scale product; their coverage targets the generated cross difference, not an assumed zero.',
    'Robust intervals address score covariance; they do not repair omitted structure or redefine a latent component.',
    '', 'See `tables/` for denominators, MCSEs, Wilson Monte Carlo intervals, paired differences, parameter/contrast recovery, and numerical reliability.',
    'See `raw/` for compressed replication-level records, `figures/` for PNG/PDF graphics, and `frozen_source/` for the exact implementation.')
  writeLines(note,file.path(output,'RESULTS.md'))
  list(complete=complete,checkpoints=nrow(manifest),pipeline_errors=sum(nzchar(manifest$pipeline_error)))
}
if(sys.nframe()==0) {
  a<-grep('^--run=',commandArgs(TRUE),value=TRUE)
  if(!length(a))stop('Supply --run=<run directory>')
  print(summarize_run(sub('^--run=','',a[1])))
}
