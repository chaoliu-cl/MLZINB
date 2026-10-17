# Run roles

`production_2026-10-16` is the frozen 58-condition, 500-repetition production run.
Its live processes, checkpoint files, and worker progress determine current status.
Its first full repetition is an execution safeguard; the production results are
provisional until all 29,000 checkpoints are complete without pipeline errors.

The other directories contain software development and execution checks, not
publication evidence. None is pooled into production summaries.

- `runner_final_check`: one opposite-sign dataset under the final source; the
  complete runner, frozen reporting, and identical-command resumption passed.
- `hurdle_final_check`: one hurdle dataset under the final source; the runner and
  stress-only reporting passed, with component-localization accuracy undefined.
- `smoke_stress_eight`: targeted fits for composition, slopes, dispersion,
  heavy tails, NB1, and dependence. All eight checkpoints completed without pipeline
  errors. The original report encountered an empty-core-figure error; reporting
  was corrected and its provisional report rebuilt from the same checkpoints.
- `smoke_stress_final`: a binary-context execution check; reporting was rebuilt
  after the same stress-only-figure correction.
- `smoke_development_01`: early worker initialization check, superseded.
- `smoke_development_02`: early core checks, interrupted when the verified
  production implementation replaced the development controller.

The independent 137-check suite and benchmark are in `../verification/`.
