suppressPackageStartupMessages({library(data.table);library(glmmTMB)})
base <- "refit_2026-10-14_multilevel/outputs"
for(ds in c("ccd","nncs")) {
  out <- file.path(base,ds)
  r <- readRDS(file.path(out,"models","primary_joint.rds"))
  m <- r$model
  sc <- fread(file.path(out,"scaling.csv"))[sample=="primary"]
  sample_data <- fread(file.path(out,"sample_primary.csv"))
  if(ds=="ccd") {
    enrollment <- median(sample_data$MEMBER09)
    schools <- median(sample_data$SCH09)
    nd <- expand.grid(rural=c(0,1),context_z=c(-1,0,1))
    nd$context_share <- sc[variable=="context",mean] + nd$context_z*sc[variable=="context",sd]
    nd$within <- nd$rural-nd$context_share
    nd$log_enrollment <- log(enrollment)
    nd$log_enrollment_z <- (log(enrollment)-sc[variable=="log_enrollment",mean])/sc[variable=="log_enrollment",sd]
    nd$log_schools_z <- (log(schools)-sc[variable=="log_schools",mean])/sc[variable=="log_schools",sd]
    nd$city <- 0L
    nd$small <- as.integer(enrollment<500)
    nd$one_school <- as.integer(schools==1)
    nd$type2 <- 0L
    nd$state <- factor(levels(m$frame$state)[1],levels=levels(m$frame$state))
    nd$exposure_students <- enrollment
    contrast <- "rural versus non-rural; city=0, independent district, median enrollment and schools"
  } else {
    population <- median(sample_data$T_POP102)
    nd <- expand.grid(within=c(-.5,.5),context_z=c(-1,0,1))
    nd$between <- 0
    nd$gini <- sc[variable=="context",mean] + nd$context_z*sc[variable=="context",sd]
    nd$raw_tract_disadvantage <- sc[variable=="between_disadvantage",mean] + nd$within*sc[variable=="within_disadvantage",sd]
    nd$minority_z <- nd$instability_z <- nd$vacancy_z <- 0
    nd$partial <- 0L
    nd$log_exposure <- log(population*4)
    nd$city <- factor(levels(m$frame$city)[1],levels=levels(m$frame$city))
    nd$exposure_residents <- population
    contrast <- "one pooled within-city SD disadvantage contrast; city mean and controls centered, whole-tract flag"
  }
  nd$count_class_mean <- as.numeric(predict(m,newdata=nd,type="conditional",re.form=NA))
  nd$modeled_zero_class_probability <- as.numeric(predict(m,newdata=nd,type="zprob",re.form=NA))
  nd$observed_expected_count <- as.numeric(predict(m,newdata=nd,type="response",re.form=NA))
  stopifnot(max(abs(nd$observed_expected_count-(1-nd$modeled_zero_class_probability)*nd$count_class_mean))<1e-6,
    all(nd$modeled_zero_class_probability>=0 & nd$modeled_zero_class_probability<=1))
  fwrite(as.data.table(nd),file.path(out,"prediction_examples.csv"))
  ratios <- as.data.table(nd)[,.(
    conditional_count_ratio=count_class_mean[2]/count_class_mean[1],
    modeled_zero_class_odds_ratio=(modeled_zero_class_probability[2]/(1-modeled_zero_class_probability[2]))/
      (modeled_zero_class_probability[1]/(1-modeled_zero_class_probability[1])),
    observed_expected_count_ratio=observed_expected_count[2]/observed_expected_count[1]),by=context_z]
  ratios[,`:=`(contrast=contrast,random_effects="set to zero; not integrated population averages")]
  fwrite(ratios,file.path(out,"prediction_contrasts.csv"))
  print(ds)
  print(ratios)
  rm(r,m,nd,sample_data)
  gc()
}
