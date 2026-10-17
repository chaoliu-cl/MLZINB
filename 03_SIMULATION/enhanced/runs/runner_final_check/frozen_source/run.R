# Usage: Rscript run.R --mode=full --reps=500 --workers=2 --label=production_2026-10-16
# An existing label is resumed only with identical configuration and source hashes.
arg<-function(key,default) {
  x<-grep(paste0('^--',key,'='),commandArgs(TRUE),value=TRUE)
  if(length(x))sub(paste0('^--',key,'='),'',x[1]) else default
}
script<-sub('^--file=','',grep('^--file=',commandArgs(FALSE),value=TRUE)[1])
root<-dirname(normalizePath(script,winslash='/'))
Sys.setenv(OMP_NUM_THREADS='1',OPENBLAS_NUM_THREADS='1',MKL_NUM_THREADS='1')
source(file.path(root,'simulation.R'))
data.table::setDTthreads(1)
mode<-arg('mode','full');stopifnot(mode%in%c('smoke','full','calibration'))
reps<-as.integer(arg('reps',if(mode=='smoke')'1' else '500'))
workers<-as.integer(arg('workers','2'))
label<-arg('label',paste0(mode,'_2026-10-16'))
stopifnot(reps>=1L,reps<=100000L,workers>=1L,workers<=16L,grepl('^[A-Za-z0-9_-]+$',label))
grid<-condition_grid()
ids<-arg('conditions','all')
if(ids!='all')grid<-grid[condition_id%in%as.integer(strsplit(ids,',',fixed=TRUE)[[1]])]
stopifnot(nrow(grid)>0)
output<-file.path(root,'runs',label)
dir.create(output,recursive=TRUE,showWarnings=FALSE)
hashfiles<-file.path(root,c('simulation.R','run.R','summarize.R','verify.R','PROTOCOL.md'))
hashes<-tools::md5sum(hashfiles);names(hashes)<-basename(names(hashes))
if(mode=='full') {
  vh<-file.path(root,'verification','source_hashes.rds');vc<-file.path(root,'verification','checks.csv')
  if(!file.exists(vh)||!file.exists(vc)||!identical(readRDS(vh),hashes)||!all(fread(vc)$passed))
    stop('Run verify.R successfully against the current source before production.')
}
config<-list(version=simulation_version,base_seed=base_seed,mode=mode,reps=reps,
  R_version=R.version.string,
  condition_ids=grid$condition_id,hashes=hashes,
  package_versions=vapply(c('glmmTMB','TMB','sandwich','data.table'),function(p)as.character(packageVersion(p)),character(1)))
cfgpath<-file.path(output,'configuration.rds')
if(file.exists(cfgpath)) {
  if(!identical(readRDS(cfgpath),config))stop('Resume refused: configuration/source/package versions differ. Use a new label.')
} else {
  atomic_rds(config,cfgpath)
  jsonlite::write_json(config,file.path(output,'configuration.json'),auto_unbox=TRUE,pretty=TRUE)
  dir.create(file.path(output,'frozen_source'),showWarnings=FALSE)
  file.copy(hashfiles,file.path(output,'frozen_source'),overwrite=FALSE)
  writeLines(capture.output(sessionInfo()),file.path(output,'sessionInfo.txt'))
  fwrite(grid,file.path(output,'condition_grid.csv'))
}
lockfile<-file.path(output,'running.lock')
if(file.exists(lockfile))stop('A running.lock exists. Inspect its PID before removing a stale lock.')
taskgrid<-CJ(replication=seq_len(reps),condition_id=grid$condition_id)
taskgrid[,path:=file.path(output,'checkpoints',sprintf('c%03d_r%06d.rds',condition_id,replication))]
existing<-file.exists(taskgrid$path)
if(any(existing))for(i in which(existing)) {
  ck<-readRDS(taskgrid$path[i])
  if(ck$version!=simulation_version||ck$condition_id!=taskgrid$condition_id[i]||
    ck$replication!=taskgrid$replication[i]||ck$seed!=base_seed+ck$condition_id*100000+ck$replication)
    stop('Existing checkpoint identity mismatch: ',taskgrid$path[i])
}
pending<-taskgrid[!existing]
if(arg('retry-errors','false')=='true') {
  bad<-taskgrid[existing][vapply(path,function(p)!is.null(readRDS(p)$pipeline_error),logical(1))]
  if(nrow(bad)){unlink(bad$path);pending<-rbind(pending,bad)}
}
pending<-pending[order(replication,condition_id)]
if(mode=='full') {
  initial_paths<-taskgrid[replication==1L&file.exists(path)]$path
  if(length(initial_paths)&&any(vapply(initial_paths,function(p)!is.null(readRDS(p)$pipeline_error),logical(1))))
    stop('Existing first-sweep pipeline errors must be resolved before production resumes.')
}
start<-Sys.time(); done_initial<-sum(existing);completed_now<-0L;error_now<-0L
logpath<-file.path(output,'progress.log')
logline<-function(s){v<-paste(format(Sys.time(),'%Y-%m-%d %H:%M:%S'),s);cat(v,'\n');cat(v,'\n',file=logpath,append=TRUE)}
status_write<-function(state,completed,error=NA_integer_,last=NULL) {
  elapsed<-as.numeric(difftime(Sys.time(),start,units='secs'))
  speed<-if(completed_now>0)completed_now/max(elapsed,1) else NA_real_
  remaining<-nrow(taskgrid)-completed
  x<-list(state=state,mode=mode,label=label,updated=as.character(Sys.time()),pid=Sys.getpid(),
    workers=workers,conditions=nrow(grid),replications_per_condition=reps,
    planned=nrow(taskgrid),completed_checkpoints=completed,pipeline_errors_observed_this_session=error,
    wall_seconds_this_session=elapsed,estimated_seconds_remaining=remaining/speed,last_batch=last)
  tmp<-file.path(output,'status.json.tmp')
  jsonlite::write_json(x,tmp,pretty=TRUE,auto_unbox=TRUE,na='null')
  file.copy(tmp,file.path(output,'status.json'),overwrite=TRUE);unlink(tmp)
}
main<-function() {
  on.exit(unlink(lockfile),add=TRUE)
  cl<-NULL
  if(workers>1&&nrow(pending)) {
    cl<-parallel::makePSOCKcluster(workers,outfile=file.path(output,'workers.log'))
    on.exit(if(!is.null(cl))parallel::stopCluster(cl),add=TRUE)
    parallel::clusterCall(cl,function(src){Sys.setenv(OMP_NUM_THREADS='1',OPENBLAS_NUM_THREADS='1',MKL_NUM_THREADS='1');
      source(src,local=.GlobalEnv);data.table::setDTthreads(1);NULL},file.path(output,'frozen_source','simulation.R'))
  }
  status_write('running',done_initial,error_now)
  logline(sprintf('Start %s: %d planned paired datasets; %d existing; %d workers.',mode,nrow(taskgrid),done_initial,workers))
  # Dynamically schedule a full repetition sweep, one paired dataset per job.
  # Difficult boundary fits should not strand workers behind tiny batch barriers.
  # Per-model live progress and atomic checkpoints remain visible during a sweep.
  batch_size<-nrow(grid)
  batches<-if(nrow(pending))split(seq_len(nrow(pending)),
    paste(pending$replication,ave(seq_len(nrow(pending)),pending$replication,
      FUN=function(v)ceiling(seq_along(v)/batch_size)),sep='_')) else list()
  if(length(batches))batches<-batches[order(vapply(batches,min,numeric(1)))]
  for(take in batches) {
    tasks<-lapply(take,function(i)list(condition=grid[condition_id==pending$condition_id[i]],
      replication=pending$replication[i],path=pending$path[i]))
    ans<-if(is.null(cl))lapply(tasks,execute_task) else parallel::parLapplyLB(cl,tasks,execute_task,chunk.size=1L)
    a<-rbindlist(ans);completed_now<<-completed_now+nrow(a);error_now<<-error_now+sum(a$status=='pipeline_error')
    fwrite(a,file.path(output,'execution.csv'),append=file.exists(file.path(output,'execution.csv')))
    done<-sum(file.exists(taskgrid$path))
    logline(sprintf('%d/%d checkpoints; last conditions %s; median task %.1fs; pipeline errors this session %d.',
      done,nrow(taskgrid),paste(a$condition_id,collapse=','),median(a$seconds,na.rm=TRUE),error_now))
    status_write('running',done,error_now,as.data.frame(a))
    # Exercise every scenario before the long production phase. Model failures
    # remain outcomes; unexpected pipeline errors halt rather than waste a full run.
    if(mode=='full'&&max(pending$replication[take])==1L&&
      all(file.exists(taskgrid[replication==1L]$path))) {
      bad<-vapply(taskgrid[replication==1L]$path,function(p)!is.null(readRDS(p)$pipeline_error),logical(1))
      if(any(bad))stop('First-sweep pipeline errors: inspect checkpoints before continuing. No replacement datasets generated.')
      logline('First production sweep passed: every condition checkpointed without pipeline errors.')
    }
  }
  if(!is.null(cl)){parallel::stopCluster(cl);cl<-NULL}
  # This is an execution state, not a claim that all fits succeeded.
  status_write('summarizing',sum(file.exists(taskgrid$path)),error_now)
  source(file.path(output,'frozen_source','summarize.R'),local=TRUE)
  results<-summarize_run(output,make_plots=TRUE)
  state<-if(results$complete)'complete' else 'partial_or_pipeline_error'
  status_write(state,results$checkpoints,results$pipeline_errors)
  logline(sprintf('Finished aggregation: %s; %d checkpoints; %d pipeline errors.',state,results$checkpoints,results$pipeline_errors))
}
writeLines(c(paste0('pid=',Sys.getpid()),paste0('started=',Sys.time())),lockfile)
tryCatch(main(),error=function(e){status_write('interrupted_or_error',sum(file.exists(taskgrid$path)),error_now);
  logline(paste('STOP:',conditionMessage(e)));stop(e)})
