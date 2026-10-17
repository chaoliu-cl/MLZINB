files<-list.files('09_MODERATION_DATASET_SEARCH/code',pattern='\\.R$',full.names=TRUE)
for(f in files){parse(f);cat('Parsed',basename(f),'\n')}
