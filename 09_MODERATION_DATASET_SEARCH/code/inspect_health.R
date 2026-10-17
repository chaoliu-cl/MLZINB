e <- new.env()
load('09_MODERATION_DATASET_SEARCH/rwm/source/Health.rda', envir=e)
print(ls(e))
d <- e[[ls(e)[1]]]
print(dim(d)); print(names(d)); print(head(d)); print(summary(d))
write.csv(d,'09_MODERATION_DATASET_SEARCH/rwm/source/Health.csv',row.names=FALSE)
cat('People:',length(unique(d$id)),'\n')
print(table(table(d$id)))
print(table(d$year))
