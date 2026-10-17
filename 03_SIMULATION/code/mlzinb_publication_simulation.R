# Publication simulation for contextual moderation in multilevel ZINB models.
# A small run can be requested with MLZINB_PUB_NREP; 500+ replications per
# condition are recommended for final Monte Carlo inference.

suppressPackageStartupMessages({
  library(glmmTMB)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(parallel)
})

set.seed(20260807)
options(dplyr.summarise.inform = FALSE, scipen = 999)

script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
script_dir <- if (length(script_arg)) {
  dirname(normalizePath(sub("^--file=", "", script_arg[1]), winslash = "/"))
} else {
  getwd()
}
default_root <- normalizePath(file.path(script_dir, "..", ".."), winslash = "/", mustWork = FALSE)
package_root <- Sys.getenv("MLZINB_PACKAGE_ROOT", unset = default_root)
run_label <- Sys.getenv("MLZINB_SIM_LABEL", unset = "publication_full")
output_dir <- file.path(package_root, "03_SIMULATION", "outputs", run_label)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

n_reps <- max(1L, as.integer(Sys.getenv("MLZINB_PUB_NREP", unset = "500")))
n_cores <- min(
  max(1L, as.integer(Sys.getenv("MLZINB_PUB_CORES", unset = "4"))),
  max(1L, parallel::detectCores(logical = FALSE) - 1L),
  6L
)

scenario_grid <- data.frame(
  scenario = c(
    "Null moderation", "Additive context only", "NB truth",
    rep("Inflation only", 2), rep("Count only", 2),
    rep("Dual same sign", 2), rep("Dual opposite sign", 2)
  ),
  effect = c(0, 0, 0, rep(c(0.15, 0.30), 4)),
  stringsAsFactors = FALSE
)

design_grid <- data.frame(
  design = c("40 clusters x 30", "80 clusters x 60"),
  n_clusters = c(40L, 80L),
  cluster_size = c(30L, 60L),
  stringsAsFactors = FALSE
)

condition_grid <- merge(scenario_grid, design_grid, all = TRUE)
condition_grid <- condition_grid[order(
  match(condition_grid$scenario, unique(scenario_grid$scenario)),
  condition_grid$effect, condition_grid$n_clusters
), ]
rownames(condition_grid) <- NULL
condition_grid$condition_id <- seq_len(nrow(condition_grid))
condition_grid$zi_cross_true <- with(
  condition_grid,
  ifelse(
    scenario %in% c("Inflation only", "Dual same sign"), effect,
    ifelse(scenario == "Dual opposite sign", -effect, 0)
  )
)
condition_grid$count_cross_true <- with(
  condition_grid,
  ifelse(scenario %in% c("Count only", "Dual same sign", "Dual opposite sign"), effect, 0)
)
condition_grid$zi_context_true <- ifelse(
  condition_grid$scenario %in% c("Null moderation", "NB truth"), 0, 0.30
)
condition_grid$count_context_true <- ifelse(
  condition_grid$scenario %in% c("Null moderation", "NB truth"), 0, 0.15
)
condition_grid$true_model <- with(
  condition_grid,
  ifelse(
    scenario == "NB truth", "NB",
    ifelse(
      scenario %in% c("Null moderation", "Additive context only"), "ZINB_additive",
      ifelse(
        scenario == "Inflation only", "ZINB_zi_cross",
        ifelse(scenario == "Count only", "ZINB_count_cross", "ZINB_both_cross")
      )
    )
  )
)

write.csv(condition_grid, file.path(output_dir, "publication_condition_grid.csv"), row.names = FALSE)

fit_control <- glmmTMBControl(
  profile = FALSE,
  optCtrl = list(iter.max = 600, eval.max = 600)
)

safe_predict <- function(model, type, newdata) {
  tryCatch(
    as.numeric(predict(model, newdata = newdata, type = type, allow.new.levels = TRUE)),
    error = function(e) rep(NA_real_, nrow(newdata))
  )
}

extract_term <- function(model, component, term) {
  tab <- tryCatch(summary(model)$coefficients[[component]], error = function(e) NULL)
  if (is.null(tab) || !term %in% rownames(tab)) {
    return(c(estimate = NA_real_, std_error = NA_real_, p_value = NA_real_))
  }
  c(
    estimate = tab[term, "Estimate"],
    std_error = tab[term, "Std. Error"],
    p_value = tab[term, "Pr(>|z|)"]
  )
}

generate_dataset <- function(cond_row, seed) {
  set.seed(seed)
  cluster <- data.frame(
    cluster_id = factor(seq_len(cond_row$n_clusters)),
    context = rnorm(cond_row$n_clusters),
    zi_random = rnorm(cond_row$n_clusters, sd = 0.50),
    count_random = rnorm(cond_row$n_clusters, sd = 0.35)
  )
  dat <- cluster[rep(seq_len(nrow(cluster)), each = cond_row$cluster_size), ]
  dat$unit <- sequence(rep(cond_row$cluster_size, cond_row$n_clusters))
  dat$x <- rnorm(nrow(dat))
  dat$covariate <- rbinom(nrow(dat), 1, 0.45)

  eta_count <- 0.70 + 0.40 * dat$x +
    cond_row$count_context_true * dat$context + 0.25 * dat$covariate +
    cond_row$count_cross_true * dat$x * dat$context + dat$count_random
  dat$mu_true <- exp(eta_count)

  if (cond_row$scenario == "NB truth") {
    dat$pi_true <- 0
    dat$structural_zero <- 0L
  } else {
    eta_zi <- -0.55 - 0.80 * dat$x +
      cond_row$zi_context_true * dat$context + 0.35 * dat$covariate +
      cond_row$zi_cross_true * dat$x * dat$context + dat$zi_random
    dat$pi_true <- plogis(eta_zi)
    dat$structural_zero <- rbinom(nrow(dat), 1, dat$pi_true)
  }

  dat$latent_count <- rnbinom(nrow(dat), mu = dat$mu_true, size = 1.40)
  dat$y <- ifelse(dat$structural_zero == 1L, 0L, dat$latent_count)
  dat$overall_mean_true <- (1 - dat$pi_true) * dat$mu_true
  dat
}

fit_model_set <- function(dat) {
  count_additive <- y ~ x + context + covariate + (1 | cluster_id)
  count_cross <- y ~ x * context + covariate + (1 | cluster_id)
  zi_fixed <- ~1
  zi_random <- ~1 + (1 | cluster_id)
  zi_additive <- ~x + context + covariate + (1 | cluster_id)
  zi_cross <- ~x * context + covariate + (1 | cluster_id)

  specs <- list(
    NB = list(count = count_additive, zi = ~0),
    ZINB_fixed_inflation = list(count = count_additive, zi = zi_fixed),
    ZINB_random_inflation = list(count = count_additive, zi = zi_random),
    ZINB_additive = list(count = count_additive, zi = zi_additive),
    ZINB_count_cross = list(count = count_cross, zi = zi_additive),
    ZINB_zi_cross = list(count = count_additive, zi = zi_cross),
    ZINB_both_cross = list(count = count_cross, zi = zi_cross)
  )

  fits <- lapply(specs, function(spec) {
    tryCatch(
      suppressWarnings(glmmTMB(
        spec$count, ziformula = spec$zi, family = nbinom2(),
        data = dat, control = fit_control
      )),
      error = function(e) NULL
    )
  })
  fits
}

evaluate_fit <- function(model, model_name, dat) {
  empty <- data.frame(
    model = model_name, converged = 0L, AIC = NA_real_,
    zi_pred_mse = NA_real_, overall_mean_mse = NA_real_,
    zi_estimate = NA_real_, zi_se = NA_real_, zi_p = NA_real_,
    count_estimate = NA_real_, count_se = NA_real_, count_p = NA_real_,
    stringsAsFactors = FALSE
  )
  if (is.null(model)) return(empty)

  ok <- isTRUE(model$sdr$pdHess) && isTRUE(model$fit$convergence == 0)
  pred_zi <- if (model_name == "NB") rep(0, nrow(dat)) else safe_predict(model, "zprob", dat)
  pred_mean <- safe_predict(model, "response", dat)
  zi_term <- extract_term(model, "zi", "x:context")
  count_term <- extract_term(model, "cond", "x:context")

  data.frame(
    model = model_name,
    converged = as.integer(ok),
    AIC = if (ok) tryCatch(AIC(model), error = function(e) NA_real_) else NA_real_,
    zi_pred_mse = mean((pred_zi - dat$pi_true)^2, na.rm = TRUE),
    overall_mean_mse = mean((pred_mean - dat$overall_mean_true)^2, na.rm = TRUE),
    zi_estimate = zi_term["estimate"], zi_se = zi_term["std_error"], zi_p = zi_term["p_value"],
    count_estimate = count_term["estimate"], count_se = count_term["std_error"],
    count_p = count_term["p_value"],
    stringsAsFactors = FALSE
  )
}

run_replication <- function(cond_row, rep_id) {
  dat <- generate_dataset(cond_row, 700000L + cond_row$condition_id * 1000L + rep_id)
  fits <- fit_model_set(dat)
  result <- do.call(rbind, Map(
    function(fit, name) evaluate_fit(fit, name, dat),
    fits, names(fits)
  ))
  finite_aic <- is.finite(result$AIC)
  best <- if (any(finite_aic)) result$model[which.min(ifelse(finite_aic, result$AIC, Inf))] else NA_character_

  result$condition_id <- cond_row$condition_id
  result$replication <- rep_id
  result$scenario <- cond_row$scenario
  result$effect <- cond_row$effect
  result$design <- cond_row$design
  result$n_clusters <- cond_row$n_clusters
  result$cluster_size <- cond_row$cluster_size
  result$zi_cross_true <- cond_row$zi_cross_true
  result$count_cross_true <- cond_row$count_cross_true
  result$true_model <- cond_row$true_model
  result$observed_zero_rate <- mean(dat$y == 0)
  result$best_model <- best
  result$selected <- as.integer(result$model == best)
  result$correct_selection <- as.integer(best == cond_row$true_model)
  result
}

run_condition <- function(i) {
  cond_row <- condition_grid[i, , drop = FALSE]
  do.call(rbind, lapply(seq_len(n_reps), function(r) run_replication(cond_row, r)))
}

cat("Publication ML-ZINB simulation\n")
cat("Conditions:", nrow(condition_grid), "\n")
cat("Replications per condition:", n_reps, "\n")
cat("Model fits requested:", nrow(condition_grid) * n_reps * 7L, "\n")

if (n_cores > 1L) {
  cl <- makeCluster(n_cores)
  on.exit(try(stopCluster(cl), silent = TRUE), add = TRUE)
  clusterEvalQ(cl, suppressPackageStartupMessages(library(glmmTMB)))
  clusterExport(
    cl,
    c(
      "condition_grid", "n_reps", "fit_control", "safe_predict", "extract_term",
      "generate_dataset", "fit_model_set", "evaluate_fit", "run_replication",
      "run_condition"
    ),
    envir = environment()
  )
  raw <- do.call(rbind, parLapply(cl, seq_len(nrow(condition_grid)), run_condition))
  stopCluster(cl)
} else {
  raw <- do.call(rbind, lapply(seq_len(nrow(condition_grid)), run_condition))
}

write.csv(raw, file.path(output_dir, "publication_raw_results.csv"), row.names = FALSE)

model_performance <- raw |>
  group_by(
    scenario, effect, design, n_clusters, cluster_size,
    zi_cross_true, count_cross_true, true_model, model
  ) |>
  summarise(
    replications = n_distinct(replication),
    convergence_rate = mean(converged),
    mean_AIC = mean(AIC, na.rm = TRUE),
    selection_rate = mean(selected, na.rm = TRUE),
    correct_selection_rate = mean(correct_selection, na.rm = TRUE),
    mean_zero_rate = mean(observed_zero_rate),
    zi_prediction_mse = mean(zi_pred_mse, na.rm = TRUE),
    overall_mean_mse = mean(overall_mean_mse, na.rm = TRUE),
    .groups = "drop"
  )
write.csv(model_performance, file.path(output_dir, "publication_model_performance.csv"), row.names = FALSE)

parameter_rows <- bind_rows(
  raw |>
    filter(model %in% c("ZINB_zi_cross", "ZINB_both_cross")) |>
    transmute(
      scenario, effect, design, n_clusters, cluster_size, model,
      component = "Inflation", true_value = zi_cross_true,
      estimate = zi_estimate, std_error = zi_se, p_value = zi_p
    ),
  raw |>
    filter(model %in% c("ZINB_count_cross", "ZINB_both_cross")) |>
    transmute(
      scenario, effect, design, n_clusters, cluster_size, model,
      component = "Count", true_value = count_cross_true,
      estimate = count_estimate, std_error = count_se, p_value = count_p
    )
) |>
  mutate(
    error = estimate - true_value,
    covered = as.integer(
      estimate - 1.96 * std_error <= true_value &
        estimate + 1.96 * std_error >= true_value
    ),
    significant = as.integer(p_value < 0.05)
  )

parameter_performance <- parameter_rows |>
  group_by(
    scenario, effect, design, n_clusters, cluster_size,
    model, component, true_value
  ) |>
  summarise(
    usable_replications = sum(is.finite(estimate) & is.finite(std_error)),
    mean_estimate = mean(estimate, na.rm = TRUE),
    empirical_sd = sd(estimate, na.rm = TRUE),
    average_se = mean(std_error, na.rm = TRUE),
    bias = mean(error, na.rm = TRUE),
    mse = mean(error^2, na.rm = TRUE),
    rmse = sqrt(mse),
    coverage_95 = mean(covered, na.rm = TRUE),
    rejection_rate = mean(significant, na.rm = TRUE),
    rejection_mcse = sqrt(rejection_rate * (1 - rejection_rate) / usable_replications),
    coverage_mcse = sqrt(coverage_95 * (1 - coverage_95) / usable_replications),
    .groups = "drop"
  )
write.csv(
  parameter_performance,
  file.path(output_dir, "publication_parameter_performance.csv"),
  row.names = FALSE
)

selection <- raw |>
  distinct(condition_id, replication, scenario, effect, design, true_model, best_model, correct_selection) |>
  group_by(scenario, effect, design, true_model, best_model) |>
  summarise(selection_rate = n() / n_reps, .groups = "drop")
write.csv(selection, file.path(output_dir, "publication_selection_rates.csv"), row.names = FALSE)

danger <- model_performance |>
  filter(scenario %in% c("Inflation only", "Dual same sign", "Dual opposite sign")) |>
  group_by(scenario, effect, design) |>
  mutate(
    reference_mse = zi_prediction_mse[model == ifelse(
      scenario == "Inflation only", "ZINB_zi_cross", "ZINB_both_cross"
    )][1],
    relative_zi_mse = zi_prediction_mse / reference_mse
  ) |>
  ungroup()
write.csv(danger, file.path(output_dir, "publication_inflation_omission_cost.csv"), row.names = FALSE)

model_colors <- c(
  "NB" = "#6C757D", "ZINB_fixed_inflation" = "#B56576",
  "ZINB_random_inflation" = "#E09F3E", "ZINB_additive" = "#3D5A80",
  "ZINB_count_cross" = "#2A9D8F", "ZINB_zi_cross" = "#0077B6",
  "ZINB_both_cross" = "#9B2226"
)

p_danger <- danger |>
  filter(model %in% c(
    "ZINB_fixed_inflation", "ZINB_random_inflation", "ZINB_additive",
    "ZINB_zi_cross", "ZINB_both_cross"
  )) |>
  ggplot(aes(x = model, y = relative_zi_mse, fill = model)) +
  geom_hline(yintercept = 1, linetype = "dashed", color = "grey35") +
  geom_col(width = 0.72) +
  facet_grid(scenario ~ design + effect, scales = "free_y") +
  scale_fill_manual(values = model_colors, guide = "none") +
  labs(
    title = "Cost of omitting contextual moderation from the inflation component",
    subtitle = "Structural-zero probability MSE relative to the correctly specified interaction model",
    x = NULL, y = "Relative structural-zero MSE (correct model = 1)"
  ) +
  theme_minimal(base_size = 10) +
  theme(axis.text.x = element_text(angle = 35, hjust = 1), panel.grid.minor = element_blank())
ggsave(file.path(output_dir, "publication_inflation_omission_cost.png"), p_danger, width = 15, height = 9, dpi = 180)

p_selection <- selection |>
  filter(!is.na(best_model)) |>
  ggplot(aes(x = best_model, y = scenario, fill = selection_rate)) +
  geom_tile(color = "white") +
  geom_text(aes(label = sprintf("%.2f", selection_rate)), size = 3) +
  facet_grid(design ~ effect, scales = "free_x", space = "free_x") +
  scale_fill_gradient(low = "#F5F1E8", high = "#005F73", limits = c(0, 1)) +
  labs(
    title = "AIC model-selection rates across data-generating mechanisms",
    subtitle = "The correct model differs by row; no interaction model is expected to dominate every scenario",
    x = NULL, y = NULL, fill = "Rate"
  ) +
  theme_minimal(base_size = 10) +
  theme(axis.text.x = element_text(angle = 35, hjust = 1), panel.grid = element_blank())
ggsave(file.path(output_dir, "publication_selection_heatmap.png"), p_selection, width = 15, height = 8, dpi = 180)

p_recovery <- parameter_performance |>
  filter(model == "ZINB_both_cross") |>
  ggplot(aes(x = true_value, y = mean_estimate, color = component)) +
  geom_abline(intercept = 0, slope = 1, linetype = "dashed", color = "grey40") +
  geom_point(size = 2.5) +
  facet_grid(scenario ~ design) +
  scale_color_manual(values = c("Count" = "#2A9D8F", "Inflation" = "#9B2226")) +
  labs(
    title = "Recovery of count and inflation interaction parameters",
    subtitle = "Points show Monte Carlo mean estimates; diagonal line denotes unbiased recovery",
    x = "True interaction", y = "Mean estimate", color = NULL
  ) +
  theme_minimal(base_size = 10) +
  theme(legend.position = "top", panel.grid.minor = element_blank())
ggsave(file.path(output_dir, "publication_parameter_recovery.png"), p_recovery, width = 11, height = 11, dpi = 180)

summary_lines <- c(
  "Publication ML-ZINB simulation run",
  "",
  paste0("Run label: ", run_label),
  paste0("Conditions: ", nrow(condition_grid)),
  paste0("Replications per condition: ", n_reps),
  paste0("Requested model fits: ", nrow(condition_grid) * n_reps * 7L),
  "",
  "Truth cases: null moderation; additive contextual effects only; NB truth; inflation-only; count-only; dual same-sign; dual opposite-sign.",
  "Compared models: NB; fixed-inflation ZINB; random-inflation-only ZINB; additive ZINB; count-cross ZINB; inflation-cross ZINB; both-cross ZINB.",
  "",
  if (n_reps < 200) {
    "IMPORTANT: This is a pilot run. Rates, coverage, and Monte Carlo standard errors are not publication estimates. Rerun with MLZINB_PUB_NREP=500 or larger."
  } else {
    "This run meets the prespecified minimum of 500 replications per condition."
  }
)
writeLines(summary_lines, file.path(output_dir, "publication_simulation_run_note.txt"))
cat(paste(summary_lines, collapse = "\n"), "\n")
