#!/usr/bin/env Rscript
# Generate the figures for benchmark/report.md from benchmark/results/*.csv.
#
# Usage: Rscript benchmark/make_figures.R
# Regenerates benchmark/results/figures/*.png from the results CSVs alone.
# The script resolves the results directory from its own location, so it
# can be run from any working directory.

suppressPackageStartupMessages(library(ggplot2))

args <- commandArgs(trailingOnly = FALSE)
script <- sub("--file=", "", args[grep("--file=", args)])
results <- file.path(dirname(normalizePath(script)), "results")
figures <- file.path(results, "figures")
dir.create(figures, showWarnings = FALSE, recursive = TRUE)

read_res <- function(name) read.csv(file.path(results, name), stringsAsFactors = FALSE)

summary <- read_res("summary.csv")
netlogo_ticks <- read_res("netlogo_ticks.csv")
julia_ticks <- read_res("julia_ticks.csv")

theme_set(theme_bw(base_size = 11))
impl_colors <- c(NetLogo = "#D55E00", Julia = "#0072B2")

# (a) Per-tick time vs population: raw per-tick values of the pop sweep
# at 20 ticks (8 repetitions x 20 ticks per population), log-log, with
# per-(impl, N) medians overlaid.
pop_ticks <- subset(summary, group == "pop" & ticks == 20)$config_id
raw <- rbind(
  data.frame(impl = "NetLogo", agents = netlogo_ticks$agents_per_gender,
             seconds = netlogo_ticks$seconds,
             config_id = netlogo_ticks$config_id,
             stringsAsFactors = FALSE),
  data.frame(impl = "Julia", agents = julia_ticks$agents_per_gender,
             seconds = julia_ticks$seconds,
             config_id = julia_ticks$config_id,
             stringsAsFactors = FALSE)
)
raw <- subset(raw, config_id %in% pop_ticks)
med <- aggregate(seconds ~ impl + agents, data = raw, FUN = median)

fig_a <- ggplot(raw, aes(agents, seconds, color = impl)) +
  geom_point(alpha = 0.12, size = 0.7) +
  geom_line(data = med, aes(group = impl), linewidth = 0.9) +
  geom_point(data = med, size = 2.2) +
  scale_x_log10(breaks = c(25, 50, 100, 200, 400, 800)) +
  scale_y_log10() +
  scale_color_manual(values = impl_colors) +
  labs(x = "agents per gender (N)", y = "per-tick seconds (log scale)",
       color = "implementation",
       title = "Per-tick time vs population (20-tick runs, all ticks and repetitions)")
ggsave(file.path(figures, "per_tick_vs_population.png"), fig_a,
       width = 8, height = 5, dpi = 150)

# (b) Median total time vs ticks per population, both implementations.
pop <- subset(summary, group == "pop")
pop$N <- factor(pop$agents_per_gender, levels = c(25, 50, 100, 200, 400, 800))
totals <- rbind(
  data.frame(impl = "NetLogo", ticks = pop$ticks, N = pop$N,
             seconds = pop$netlogo_median_total_s, stringsAsFactors = FALSE),
  data.frame(impl = "Julia", ticks = pop$ticks, N = pop$N,
             seconds = pop$julia_median_total_s, stringsAsFactors = FALSE)
)
fig_b <- ggplot(totals, aes(ticks, seconds, color = N, group = N)) +
  geom_line(linewidth = 0.8) + geom_point(size = 1.8) +
  facet_wrap(~impl) +
  scale_x_log10(breaks = c(1, 5, 20, 50)) +
  scale_y_log10() +
  labs(x = "ticks (log scale)", y = "median total seconds (log scale)",
       title = "Total run time vs run length (medians of 8 measured repetitions)")
ggsave(file.path(figures, "total_vs_ticks.png"), fig_b,
       width = 8.5, height = 5, dpi = 150)

# (c) Per-tick cost over the run: median per-tick seconds vs model step
# for two configs (NetLogo tick k = k-th go call; Julia tick j = (j+1)-th
# step_model! call; both aligned to call index 1..T).
per_step <- function(df, impl, cfg) {
  d <- df[df$config_id == cfg, ]
  steps <- sort(unique(d$tick))
  data.frame(impl = impl, config_id = cfg, call = steps + if (impl == "Julia") 1 else 0,
             seconds = sapply(steps, function(k) median(d[d$tick == k, ]$seconds)),
             stringsAsFactors = FALSE)
}
curve <- rbind(
  per_step(netlogo_ticks, "NetLogo", "pop_n100_t20"),
  per_step(julia_ticks, "Julia", "pop_n100_t20"),
  per_step(netlogo_ticks, "NetLogo", "conf_0"),
  per_step(julia_ticks, "Julia", "conf_0")
)
curve$config <- ifelse(curve$config_id == "conf_0",
                       "conformism 0", "base config (conformism 10)")
fig_c <- ggplot(curve, aes(call, seconds, color = impl, linetype = config)) +
  geom_line(linewidth = 0.9) + geom_point(size = 1.4) +
  scale_y_log10() +
  scale_color_manual(values = impl_colors) +
  labs(x = "model step (go call / step_model! call)",
       y = "median per-step seconds (log scale)",
       color = "implementation", linetype = "configuration",
       title = "Per-step cost over the run (tick index alignment, see caption)")
ggsave(file.path(figures, "per_tick_over_run.png"), fig_c,
       width = 8, height = 5, dpi = 150)

# (d) Warm speedup per config, faceted by sweep group.
summary$label <- summary$config_id
summary$label <- sub("^pop_n([0-9]+)_t([0-9]+)$", "N\\1 T\\2", summary$label)
summary$label <- sub("^(net|util|conf)_", "", summary$label)
summary$grp <- factor(summary$group, levels = c("pop", "net", "util", "conf"))
summary$label <- factor(summary$label, levels = unique(summary$label))
fig_d <- ggplot(summary, aes(label, speedup_netlogo_over_julia, fill = grp)) +
  geom_col(show.legend = FALSE) +
  geom_hline(yintercept = 1, linewidth = 0.4, linetype = "dashed") +
  facet_wrap(~grp, scales = "free_x", ncol = 1) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 7)) +
  labs(x = "configuration", y = "speedup NetLogo / Julia (median totals)",
       title = "Warm speedup by configuration (values above 1: Julia faster)")
ggsave(file.path(figures, "speedup_by_config.png"), fig_d,
       width = 8, height = 9, dpi = 150)

cat("wrote", paste(list.files(figures, pattern = "\\.png$"), collapse = ", "),
    "to", figures, "\n")
