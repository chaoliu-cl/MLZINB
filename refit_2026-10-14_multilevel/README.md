# CCD and NNCS refits

Large model artifacts use lossless xz compression inside their existing `.rds`
files. Read them normally with `readRDS(path)`; R detects the compression
automatically. Git LFS is not required.

Save regenerated model artifacts with `saveRDS(result, path, compress="xz")`
to keep them below GitHub's 100 MiB file limit. The refit scripts use this
setting. Compression preserves the serialized model contents.

See `protocol.md` for the model specifications and `refit_results.md` for
the retained results.
