suppressPackageStartupMessages({library(data.table);library(glmmTMB)})
for(ds in c("ccd","nncs")) {
  out <- file.path("refit_2026-10-14_multilevel/outputs",ds)
  completed <- list.files(file.path(out,"logs"),pattern="_metrics.csv$",full.names=TRUE)
  rows <- list()
  for(path in completed) {
    id <- sub("_metrics.csv$","",basename(path))
    r <- readRDS(file.path(out,"models",paste0(id,".rds")))
    rows[[id]] <- list(coefficients=r$coefficients,metrics=r$metrics,random=r$random_effects)
    rm(r)
    gc(verbose=FALSE)
  }
  fwrite(rbindlist(lapply(rows,`[[`,"coefficients"),fill=TRUE),file.path(out,"completed_coefficients.csv"))
  fwrite(rbindlist(lapply(rows,`[[`,"metrics"),fill=TRUE),file.path(out,"completed_metrics.csv"))
  fwrite(rbindlist(lapply(rows,`[[`,"random"),fill=TRUE),file.path(out,"completed_random_effects.csv"))
  cat(ds,"completed",length(rows),"models\n")
}
