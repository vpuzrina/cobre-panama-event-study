# =============================================================================
# Cobre Panama event study - Step 3: robustness checks and placebo test
#
# Runs 02_event_study.R several times with different settings and compares the
# headline results. Then a placebo test: the same CARs on all eligible random dates (up to 1,000)
# with no Cobre Panama news, to see how unusual the real event CARs are.
#
# Input:  same as 02_event_study.R
# Output (in results_robustness/):
#   <run>/...                 full results of each run (same files as results/)
#   compare_firm.csv          FM and FNV, core events, main window, all runs
#   compare_group.csv         group mean CARs, core events, main window, all runs
#   placebo_draws.csv         group CARs [0,+1] on each random date
#   placebo_summary.csv       real CAR vs placebo distribution
#   fig_placebo.png           placebo distributions with the real events marked
#
# Stars: *** p < 0.01, ** p < 0.05, * p < 0.10 (SQ test for single firms,
# portfolio test for groups).
# Runtime: a few minutes, mostly the placebo.
# =============================================================================

library(tidyverse)

out_root <- "results_robustness"
dir.create(out_root, showWarnings = FALSE)

# ---- 1. The runs ---------------------------------------------------------------
runs <- list(
  main        = list(),                          # same as 02 defaults
  no_copper   = list(use_copper = FALSE),        # one-factor market model
  world_index = list(market_col = "world_ret"),  # MSCI ACWI as the market
  short_est   = list(est_start = -120,           # estimation days -120..-30
                     min_est_obs = 50),          # (~90 days, fewer near 2026 events)
  no_buffer   = list(other_event_buffer = 0)     # keep days near other events
)

all_firm  <- list()
all_group <- list()

for (nm in names(runs)) {
  message("Run: ", nm)
  settings_override <- modifyList(runs[[nm]],
                                  list(out_dir = file.path(out_root, nm),
                                       quiet = TRUE))
  source("02_event_study.R")
  all_firm[[nm]]  <- car_firm  %>% mutate(run = nm)
  all_group[[nm]] <- car_group %>% mutate(run = nm)
  if (nm == "main") {                 # keep what the placebo needs
    panel_main  <- panel
    groups_main <- groups
    ev_main     <- ev_all
    car_firm_main  <- car_firm
    car_group_main <- car_group
  }
}
rm(settings_override)

stars <- function(p) case_when(p < 0.01 ~ "***", p < 0.05 ~ "**",
                               p < 0.10 ~ "*", TRUE ~ "")

# ---- 2. Comparison tables ----------------------------------------------------
compare_firm <- bind_rows(all_firm) %>%
  filter(ticker %in% c("FM.TO", "FNV.TO"), use == "core", main) %>%
  transmute(ticker, event_id, window, run,
            cell = paste0(sprintf("%.1f", 100 * (exp(car) - 1)), stars(p_sq))) %>%
  pivot_wider(names_from = run, values_from = cell) %>%
  arrange(ticker, event_id)

compare_group <- bind_rows(all_group) %>%
  filter(use == "core", main) %>%
  transmute(event_id, group, window, run,
            cell = paste0(sprintf("%.2f", 100 * mean_car), stars(p_portfolio))) %>%
  pivot_wider(names_from = run, values_from = cell) %>%
  arrange(event_id, group)

write_csv(compare_firm,  file.path(out_root, "compare_firm.csv"))
write_csv(compare_group, file.path(out_root, "compare_group.csv"))

cat("\n=== FM and FNV: CAR in % (simple), main window, by run ===\n")
print(compare_firm, n = Inf, width = Inf)
cat("\n=== Groups: mean CAR in % (log), main window, by run ===\n")
print(compare_group, n = Inf, width = Inf)

# ---- 3. Placebo test -----------------------------------------------------------
# Random reference dates from mid-2023 to mid-Oct 2026, at least 15 calendar
# days away from every Cobre Panama event. For each date: the same main model
# (home index + copper, days -250..-30) and CAR over [0,+1] for every firm,
# then the mean per group.
set.seed(2026)
n_placebo <- 1000

panel_split_main <- split(panel_main, panel_main$ticker)
event_refs <- unique(ev_main$day0_ref)

candidates <- panel_main %>%
  filter(ticker == "FM.TO", date >= as.Date("2023-08-15"),
         date <= as.Date("2026-10-15")) %>%
  pull(date)
candidates <- candidates[sapply(candidates, function(d)
  all(abs(as.numeric(d - event_refs)) > 15))]
# There are fewer eligible trading days than 1,000, so use all of them
n_placebo <- min(n_placebo, length(candidates))
placebo_dates <- sample(candidates, n_placebo, replace = FALSE)

car_at <- function(tk, d0) {
  d  <- panel_split_main[[tk]]
  t0 <- d$tidx[d$date >= d0][1]
  if (is.na(t0)) return(NA_real_)
  rel <- d$tidx - t0
  est <- d[rel >= -250 & rel <= -30, ]
  w   <- d[rel >= 0 & rel <= 1, ]
  if (nrow(est) < 150 || nrow(w) < 2) return(NA_real_)
  m <- lm(ret ~ mkt + cu, data = est)
  sum(w$ret - predict(m, newdata = w))
}

group_map <- groups_main %>% filter(!str_starts(group, "excluded"))
message("Placebo: ", n_placebo, " random dates x ", nrow(group_map), " firms ...")

placebo_draws <- map_dfr(seq_along(placebo_dates), function(i) {
  d0 <- placebo_dates[i]
  tibble(draw = i, date = d0, ticker = group_map$ticker,
         car = map_dbl(group_map$ticker, car_at, d0 = d0))
}) %>%
  left_join(group_map %>% select(ticker, group), by = "ticker") %>%
  group_by(draw, date, group) %>%
  summarise(car = mean(car, na.rm = TRUE), .groups = "drop")

write_csv(placebo_draws, file.path(out_root, "placebo_draws.csv"))

# Real CARs, main run, window [0,+1], all core events (excluded firm-events
# left out, as in the group tests)
real <- car_firm_main %>%
  filter(use == "core", window == "[0,+1]", !excluded) %>%
  group_by(event_id, group) %>%
  summarise(real_car = mean(car), n_firms = n(), .groups = "drop")

placebo_summary <- real %>%
  left_join(placebo_draws %>% group_by(group) %>%
              summarise(pl = list(car[!is.na(car)]), .groups = "drop"),
            by = "group") %>%
  mutate(
    placebo_mean = map_dbl(pl, mean),
    placebo_sd   = map_dbl(pl, sd),
    # two-sided: share of random dates at least as far from the placebo mean
    p_placebo = map2_dbl(pl, real_car, function(x, r)
      (sum(abs(x - mean(x)) >= abs(r - mean(x))) + 1) / (length(x) + 1)),
    percentile = map2_dbl(pl, real_car, function(x, r) mean(x <= r))
  ) %>%
  select(-pl) %>%
  arrange(event_id, group)

write_csv(placebo_summary, file.path(out_root, "placebo_summary.csv"))

cat("\n=== Placebo: real CAR [0,+1] vs", n_placebo, "random dates ===\n")
placebo_summary %>%
  transmute(event_id, group, n_firms,
            real_car_pct = round(100 * real_car, 2),
            placebo_sd_pct = round(100 * placebo_sd, 2),
            percentile = round(percentile, 3), p_placebo = round(p_placebo, 3)) %>%
  print(n = Inf, width = Inf)

# ---- 4. Figure: placebo distributions with the real events -------------------
key_events <- c("E2", "E6", "F6")
fig_df  <- placebo_draws %>% filter(!is.na(car))
real_df <- real %>% filter(event_id %in% key_events)

p <- ggplot(fig_df, aes(100 * car)) +
  geom_histogram(bins = 50, fill = "grey75", colour = NA) +
  geom_vline(data = real_df, aes(xintercept = 100 * real_car, colour = event_id),
             linewidth = 0.9) +
  facet_wrap(~ group, scales = "free") +
  labs(x = "Mean CAR [0,+1] of the group, % (log)", y = "Random dates",
       colour = "Real event",
       title = paste0("Placebo test: group CARs on ", n_placebo, " random dates vs the real events"),
       subtitle = "Grey: random dates without Cobre Panama news. Lines: real events.") +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")

ggsave(file.path(out_root, "fig_placebo.png"), p, width = 11, height = 6.5, dpi = 200)

message("Done. Results saved in the ", out_root, "/ folder.")
