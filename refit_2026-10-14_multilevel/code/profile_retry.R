# Retry an unchanged specification by profiling fixed parameters during optimization.
suppressPackageStartupMessages({library(data.table);library(glmmTMB)})
args <- commandArgs(trailingOnly=TRUE)
id <- args[1]
source_out <- "refit_2026-10-14_multilevel/outputs/nncs"
candidate_out <- "refit_2026-10-14_multilevel/outputs/nncs_profile_candidates"
dir.create(file.path(candidate_out,"models"),recursive=TRUE,showWarnings=FALSE)
dir.create(file.path(candidate_out,"logs"),recursive=TRUE,showWarnings=FALSE)
file.copy(file.path(source_out,"models","primary_joint.rds"),
          file.path(candidate_out,"models","primary_joint.rds"),overwrite=TRUE)
specs <- readRDS(file.path(source_out,"model_specs.rds"))
spec <- specs[[which(vapply(specs,function(s)s$id==id,logical(1)))]]
datasets <- readRDS(file.path(source_out,"analysis_datasets.rds"))
for(s in names(datasets)) {
  needed <- unique(c(all.vars(spec$cond),all.vars(spec$zi)))
  datasets[[s]] <- as.data.frame(datasets[[s]][,needed,with=FALSE])
}
expressions <- parse(file="refit_2026-10-14_multilevel/code/refit_models.R")
definition <- Filter(function(e)is.call(e)&&identical(e[[1]],as.name("<-"))&&
  identical(e[[2]],as.name("fit_job")),as.list(expressions))
stopifnot(length(definition)==1)
eval(definition[[1]])
glmmTMBControl <- function(...) glmmTMB::glmmTMBControl(...,profile=TRUE)
glmmTMB <- function(...) {
  setTimeLimit(cpu=240,elapsed=300,transient=TRUE)
  on.exit(setTimeLimit(cpu=Inf,elapsed=Inf,transient=FALSE))
  glmmTMB::glmmTMB(...)
}
print(fit_job(spec,datasets,candidate_out))
