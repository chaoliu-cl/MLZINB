# Enhanced component-aware ML-ZINB simulation

This separate implementation preserves the original four-replication pilot. It
evaluates whether the proposed workflow detects contextual moderation, localizes
the supported component, recovers effects and response contrasts, and improves
predictions. Results are allowed to favor a simpler procedure: no dataset or
replication is replaced to obtain the desired conclusion.

## Design and deliverables

- 58 prespecified conditions: 22 core and 36 targeted stress conditions.
- 500 production repetitions per condition: **29,000 paired datasets** and
  **265,500 candidate fits**, before optimizer retries.
- Count-only, inflation-only, same-sign and opposite-sign moderation; weak and
  unequal effects; null and NB truth; cluster counts/sizes; sparse and informative
  clusters; random slopes; contextual composition; weak/absent inflation
  heterogeneity; exposure; dependence; and distributional misspecification.
- Additive, count, inflation and joint ZINBs, NB comparators, reduced inflation
  specifications, plus matched slope and undecomposed comparators where needed.
- Omnibus LR followed by conditional LR tests with Holm correction; gate and
  correction ablations; separate additive tests; count-only testing; AIC; and
  model/cluster/HAC Wald alternatives.
- False discovery and localization, detection, exact classification, numerical
  failures, bias, RMSE, SE calibration, interval coverage, paired differences,
  independent predictions and response-scale cross differences.
- Four prediction targets: latent count-process intensity, extra-zero probability, overall
  mean and total-zero probability. Undefined latent targets are explicitly omitted.
- MCSEs and Wilson Monte Carlo intervals, including zero/one observed event rates.
- PNG/PDF figures, compressed replication-level tables, retained first-replicate
  models, frozen source/configuration/package versions, resumable checkpoints.

Read [PROTOCOL.md](PROTOCOL.md) for exact equations, estimands, decision rules,
failure criteria, and limitations. The saved grid is the exhaustive design.

## Run and resume on this computer

The verified R installation is **R 4.4.2**, with glmmTMB 1.1.14. Other locally
installed R versions do not have the same libraries. Start with two workers because
available memory is limited. Each worker uses one OpenMP/BLAS thread.

From the bundle root in PowerShell:

```powershell
& 'C:\Program Files\R\R-4.4.2\bin\Rscript.exe' --vanilla .\03_SIMULATION\enhanced\verify.R

.\03_SIMULATION\enhanced\launch.ps1 -Mode smoke -Replications 1 -Workers 2 -Label smoke_all

.\03_SIMULATION\enhanced\launch.ps1 -Mode full -Replications 500 -Workers 2 -Label production_2026-10-16

.\03_SIMULATION\enhanced\launch.ps1 -Label production_2026-10-16 -Status
```

`launch.ps1` starts a hidden background process. Add `-Foreground` for a blocking
console run. A full run requires successful independent verification of the exact
current source. The launcher never treats a one-replication execution check as
production evidence. Production takes several days on two workers; use `status.json`
and `progress.log` for the measured rate/remaining-time estimate.
The first production repetition exercises all 58 scenarios. An unexpected pipeline
error stops the run after that sweep; numerical model failures remain legitimate
simulation outcomes. `task_progress/` shows each worker's current model and stage.
The controller JSON/log updates after a repetition sweep. The `-Status` command
also counts completed checkpoints directly and displays the latest worker stages,
so it shows progress within a long sweep.

Repeat the identical full command to resume after an interruption. Existing
checkpoints are preserved; seeds and results do not depend on scheduling. Changing
the repetition plan, source, conditions or package versions requires a new label.
A stale `running.lock` must be removed only after confirming its saved PID is no
longer active. A live lock prevents two controllers writing to the same run.

To rebuild a **provisional** report from currently completed checkpoints:

```powershell
& 'C:\Program Files\R\R-4.4.2\bin\Rscript.exe' --vanilla .\03_SIMULATION\enhanced\summarize.R --run=./03_SIMULATION/enhanced/runs/production_2026-10-16
```

This reads complete atomic checkpoints only. Avoid running large aggregation jobs
simultaneously on this memory-constrained computer. Full aggregation occurs
automatically after workers finish. A larger replication plan can be configured
prospectively under a new label; 500 repetitions give MCSE about .010 at a .05 rate
and .022 at .50, not .005 precision.

## Output locations and interpretation

Each `runs/<label>/` contains:

| Location | Contents |
|---|---|
| `status.json`, `progress.log` | Current computation status and measured progress |
| `configuration.json`, `condition_grid.csv` | Frozen plan, hashes and exhaustive scenarios |
| `frozen_source/`, `sessionInfo.txt` | Exact source and software environment |
| `checkpoints/` | One result per paired dataset; rejected fits remain outcomes |
| `tables/` | Publication tables with planned, completed and valid denominators |
| `raw/` | Compressed replication-level records |
| `figures/` | Localization, error, coverage, omission-cost and failure figures |
| `RESULTS.md` | Completion state and interpretation notes |
| `controller.*.log`, `workers.log` | Controller and worker diagnostics |

`verification/checks.csv` records independent tests of the DGP, mixture identities,
quadrature, prediction links/offsets, full cluster scores, delta derivatives, slope
parameter ordering, paired sample sizes, classification, reporting and resumption.
`verification/report_check/` is only a reporting check, not a simulation result.

The installed package can retain inflation BLUPs when predicting previously
observed groups with `re.form=NA`. Verification therefore uses genuinely new levels
when comparing its fixed-link predictions. The simulation's independent prediction
engine explicitly integrates the fitted random-effect distribution in both components.

Numerical failure is different from no moderation. “Neither supported” is different
from evidence of negligible effects. A global-only result remains “unlocalized.”
NB-truth inflation discoveries are operational overclaims, not regular type-I
error for an identifiable inflation coefficient. Misspecification results assess
robustness and limitations; robust SEs do not repair a wrong latent decomposition.

Use final results in the manuscript only when `status.json` reports `complete`,
`remaining_reps` is zero for every condition, and pipeline errors are zero. Rejected
model fits can remain in a correctly completed study and must still be reported.
