cat(R.version.string, "\n")
print(.libPaths())
for (p in c("glmmTMB", "data.table", "TMB", "Matrix")) {
  cat(p, if (requireNamespace(p, quietly=TRUE)) as.character(packageVersion(p)) else "MISSING", "\n")
}
print(sessionInfo())
