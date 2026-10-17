options(stringsAsFactors=FALSE)
suppressPackageStartupMessages(library(glmmTMB))
root<-normalizePath('09_MODERATION_DATASET_SEARCH/rwm',winslash='/');out<-file.path(root,'outputs')
b<-readRDS(file.path(out,'full_bundle.rds'));m<-b$models$joint;d<-b$data
stopifnot(m$fit$convergence==0,isTRUE(m$sdr$pdHess))
setup<-function(m,robust=FALSE){
 bc<-fixef(m)$cond;bz<-fixef(m)$zi;p<-length(bc);q<-length(bz)
 V<-if(robust)as.matrix(read.csv(file.path(out,'full_cluster_robust_covariance.csv'),header=FALSE)) else m$sdr$cov.fixed
 stopifnot(length(m$fit$par)==p+q+2)
 list(bc=bc,bz=bz,p=p,q=q,phi=sigma(m),V=V[seq_len(p+q+1),seq_len(p+q+1)],fc=lme4::nobars(formula(m,component='cond')),fz=lme4::nobars(formula(m,component='zi')))
}
# Common support permits -2 to +2 within-person health changes on a 0-10 scale.
ref<-d[d$x_b>=2 & d$x_b<=8,]; ref$weight<-1/as.numeric(table(ref$id)[as.character(ref$id)])
w<-ref$weight/sum(ref$weight)
write.csv(data.frame(rows=nrow(ref),people=length(unique(ref$id)),minimum_mean=min(ref$x_b),maximum_mean=max(ref$x_b)),file.path(out,'prediction_reference.csv'),row.names=FALSE)
standard<-function(s,x,sex){
 nd<-ref;nd$x_w<-x;nd$female<-sex
 X<-model.matrix(s$fc,nd)[,names(s$bc),drop=FALSE];Z<-model.matrix(s$fz,nd)[,names(s$bz),drop=FALSE]
 mu<-as.vector(exp(X%*%s$bc));pi<-as.vector(plogis(Z%*%s$bz));ph<-s$phi
 nb0<-exp(-ph*log1p(mu/ph));ey<-(1-pi)*mu;p0<-pi+(1-pi)*nb0
 wm<-function(a)sum(a*w);wc<-function(A)colSums(A*w)
 p<-s$p;q<-s$q
 G<-rbind(mu=c(wc(X*mu),rep(0,q),0),pi=c(rep(0,p),wc(Z*(pi*(1-pi))),0),expected=c(wc(X*ey),wc(Z*(-mu*pi*(1-pi))),0),total_zero=c(wc(X*((1-pi)*nb0*(-ph*mu/(ph+mu)))),wc(Z*(pi*(1-pi)*(1-nb0))),wm((1-pi)*nb0*ph*(-log1p(mu/ph)+mu/(ph+mu)))))
 value<-c(mu=wm(mu),pi=wm(pi),expected=wm(ey),total_zero=wm(p0));se<-sqrt(pmax(0,rowSums((G%*%s$V)*G)))
 lo<-value-1.96*se;hi<-value+1.96*se
 pos<-names(value)%in%c('mu','expected');lo[pos]<-exp(log(value[pos])-1.96*se[pos]/value[pos]);hi[pos]<-exp(log(value[pos])+1.96*se[pos]/value[pos])
 pp<-!pos;lo[pp]<-plogis(qlogis(value[pp])-1.96*se[pp]/(value[pp]*(1-value[pp])));hi[pp]<-plogis(qlogis(value[pp])+1.96*se[pp]/(value[pp]*(1-value[pp])))
 list(table=data.frame(x_w=x,female=sex,metric=names(value),value=unname(value),se=se,lower=lo,upper=hi,row.names=NULL),G=G)
}
s<-setup(m,TRUE);sa<-setup(b$models$additive)
grid<-seq(-2,2,by=.1)
pred<-do.call(rbind,lapply(grid,function(x)do.call(rbind,lapply(0:1,function(f)standard(s,x,f)$table))))
write.csv(pred,file.path(out,'component_predictions.csv'),row.names=FALSE)
contrasts<-function(s,label){do.call(rbind,lapply(grid,function(x){a<-standard(s,x,1);z<-standard(s,x,0);G<-a$G-z$G;v<-a$table$value-z$table$value;se<-sqrt(pmax(0,rowSums((G%*%s$V)*G)));data.frame(model=label,x_w=x,metric=a$table$metric,contrast=v,se=se,lower=v-1.96*se,upper=v+1.96*se)}))}
write.csv(rbind(contrasts(s,'joint'),contrasts(sa,'additive')),file.path(out,'sex_contrasts.csv'),row.names=FALSE)
# Compare a +1 dissatisfaction step around each person's mean, by recorded sex.
steps<-lapply(0:1,function(sex){hi<-standard(s,1,sex);lo<-standard(s,0,sex);G<-hi$G-lo$G;v<-hi$table$value-lo$table$value;se<-sqrt(pmax(0,rowSums((G%*%s$V)*G)));list(v=v,G=G,table=data.frame(female=sex,metric=hi$table$metric,change=v,se=se,lower=v-1.96*se,upper=v+1.96*se))})
write.csv(do.call(rbind,lapply(steps,`[[`,'table')),file.path(out,'one_point_health_changes.csv'),row.names=FALSE)
G<-steps[[2]]$G-steps[[1]]$G;v<-steps[[2]]$v-steps[[1]]$v;se<-sqrt(pmax(0,rowSums((G%*%s$V)*G)))
write.csv(data.frame(metric=steps[[1]]$table$metric,difference_in_changes=v,se=se,lower=v-1.96*se,upper=v+1.96*se),file.path(out,'response_scale_moderation.csv'),row.names=FALSE)
slopes<-do.call(rbind,lapply(c('cond','zi'),function(comp){
 bb<-fixef(m)[[comp]];ix<-if(comp=='cond')seq_len(s$p) else s$p+seq_len(s$q)
 VV<-s$V[ix,ix];it<-which(names(bb)%in%c('x_w:female','female:x_w'))
 do.call(rbind,lapply(0:1,function(f){L<-rep(0,length(bb));L[match('x_w',names(bb))]<-1;L[it]<-f;est<-sum(L*bb);se<-sqrt(as.numeric(t(L)%*%VV%*%L));data.frame(component=comp,female=f,log_slope=est,se=se,ratio=exp(est),lower=exp(est-1.96*se),upper=exp(est+1.96*se))}))
}))
write.csv(slopes,file.path(out,'component_simple_slopes.csv'),row.names=FALSE)
# Independent checks at actual new-data records, both random effects forced zero.
nd<-ref[seq_len(min(300,nrow(ref))),];nd$x_w<-1;nd$female<-0;nd$group<-NA
X<-model.matrix(s$fc,nd)[,names(s$bc),drop=FALSE];Z<-model.matrix(s$fz,nd)[,names(s$bz),drop=FALSE]
mm<-as.vector(exp(X%*%s$bc));pp<-as.vector(plogis(Z%*%s$bz))
stopifnot(max(abs(mm-predict(m,newdata=nd,type='conditional',re.form=NA,allow.new.levels=TRUE)))<1e-7,max(abs(pp-predict(m,newdata=nd,type='zprob',re.form=NA,allow.new.levels=TRUE)))<1e-7,max(abs((1-pp)*mm-predict(m,newdata=nd,type='response',re.form=NA,allow.new.levels=TRUE)))<1e-7)
check<-standard(s,0,0);eps<-1e-5
for(j in 1:3){sp<-sm<-s;if(j==1){sp$bc['x_w']<-sp$bc['x_w']+eps;sm$bc['x_w']<-sm$bc['x_w']-eps;k<-match('x_w',names(s$bc))};if(j==2){sp$bz['x_w']<-sp$bz['x_w']+eps;sm$bz['x_w']<-sm$bz['x_w']-eps;k<-s$p+match('x_w',names(s$bz))};if(j==3){sp$phi<-sp$phi*exp(eps);sm$phi<-sm$phi*exp(-eps);k<-s$p+s$q+1};ng<-(standard(sp,0,0)$table$value-standard(sm,0,0)$table$value)/(2*eps);stopifnot(max(abs(ng-check$G[,k]))<1e-6)}
writeLines('PASS: model predictions, zero-random-effect target, mixture identities and analytic gradients independently checked.',file.path(out,'prediction_verification.txt'))
print(slopes);print(do.call(rbind,lapply(steps,`[[`,'table')))
