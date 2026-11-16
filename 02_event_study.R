# =============================================================================
# Cobre Panama event study - Step 2: abnormal returns, CARs and tests
# Version 2 (30 Oct 2026): day 0 computed here from events.csv; per-event
# windows; firm-event exclusions (exclusions.csv); settings can be overridden
# by 03_robustness.R.
#
# Input:  data/returns_panel.csv (from 01_download_data.R), events.csv,
#         companies.csv, exclusions.csv (optional)
# Output (in results/):
#   model_params.csv            alpha, betas, sigma, R2 per firm and event
#   abnormal_returns_daily.csv  AR for each firm, event, day -10..+10
#   car_firm.csv                CAR per firm, event, window + t-test + SQ test
#   car_group.csv               group results: portfolio t, BMP, Kolari-Pynnonen,
#                               sign test
#   fig_car_fm_fnv.png          CAR paths of First Quantum and Franco-Nevada
#   run_info.txt                the settings used for this run
#
# Method (MacKinlay 1997):
#   1. For every firm and event, estimate the "normal" return on days -250..-30
#      before day 0:   R_it = a + b * R_market + g * R_copper + e
#   2. Abnormal return (AR) = actual return - predicted normal return
#   3. CAR = sum of ARs over an event window, e.g. [0,+1]
#   4. Tests: single firm -> t-test and SQ test (Gelbach, Helland & Klick 2013);
#      groups -> portfolio t-test, BMP test with the Kolari-Pynnonen (2010)
#      correction for cross-correlation, and a sign test.
#
# Day 0 for each firm = its first trading day ON or AFTER the event's reference
# date in events.csv (column first_trading_day_TSX). Asian and European markets
# close before news from the Americas arrives, so their reaction usually shows
# on day +1: that is why the main window is [0,+1].
#
# Returns are LOG returns, so CARs are log CARs (close to % changes when small).
# =============================================================================

library(tidyverse)

# Read CSV files fully into memory with one thread. The faster multi-threaded
# reader crashed R on macOS once (vroom), and these files are small anyway.
options(readr.num_threads = 1)
read_csv_safe <- function(path) read_csv(path, show_col_types = FALSE, lazy = FALSE, num_threads = 1)

# ---- Settings ----------------------------------------------------------------
# Change a default here, or let 03_robustness.R override it.
defaults <- list(
  est_start   = -250,       # estimation window start (trading days before day 0)
  est_end     = -30,        # estimation window end
  min_est_obs = 150,        # skip a firm-event with fewer usable estimation days
  use_copper  = TRUE,       # FALSE = one-factor market model
  market_col  = "mkt_ret",  # "world_ret" = MSCI ACWI instead of home index
  other_event_buffer = 5,   # drop +/- 5 days around OTHER events from estimation
  out_dir     = "results",
  quiet       = FALSE       # TRUE = no printing and no figure (robustness runs)
)
s <- modifyList(defaults,
                if (exists("settings_override")) settings_override else list())
dir.create(s$out_dir, showWarnings = FALSE, recursive = TRUE)

# ---- Event windows -----------------------------------------------------------
# "default" applies to every event without its own rows. main = the window used
# for the headline results.
windows_spec <- tribble(
  ~event_id, ~w_start, ~w_end, ~main,
  "default",  0,  0, FALSE,
  "default",  0,  1, TRUE,
  "default", -1,  1, FALSE,
  "E6",       0,  0, FALSE,  # Supreme Court ruling, during TSX hours on 28 Nov
  "E6",       1,  1, FALSE,  # president's closure order, after close on 28 Nov
  "E6",       0,  1, TRUE,   # both together (Asian firms only see them together)
  "E6",      -5,  1, FALSE,  # plus the week of court deliberations before
  "E1",      -1,  3, TRUE,   # good and bad news overlap (context only)
  "F2",       0,  0, TRUE    # day +1 has FQM's own Q4 results, US payrolls
)                            # and a +2.5% copper move

# ---- 1. Read inputs ----------------------------------------------------------
companies <- read_csv_safe("companies.csv")
panel     <- read_csv_safe("data/returns_panel.csv")
events    <- read_csv_safe("events.csv") %>%
  filter(!is.na(first_trading_day_TSX))            # drops the TC/RC context row

exclusions <- if (file.exists("exclusions.csv")) {
  read_csv_safe("exclusions.csv")
} else {
  tibble(ticker = character(), event_id = character(), reason = character())
}

# Groups. Firms whose group starts with "excluded" stay in car_firm.csv but are
# left out of all group tests. Rival miners are split by latam_share (> 0.5).
groups <- companies %>%
  filter(group != "commodity") %>%
  select(ticker = ticker_yahoo, group, any_of("latam_share"))

if ("latam_share" %in% names(groups) && any(!is.na(groups$latam_share))) {
  groups <- groups %>%
    mutate(group = case_when(
      group == "rival miner" & latam_share > 0.5 ~ "rival miner, Latin America",
      group == "rival miner"                     ~ "rival miner, other",
      TRUE                                       ~ group))
} else if (!s$quiet) {
  message("Note: no latam_share in companies.csv, rival miners are one group.")
}

# ---- 2. Panel in event time and day 0 for every firm and event ---------------
panel <- panel %>%
  mutate(mkt = replace_na(.data[[s$market_col]], 0),
         cu  = replace_na(copper_ret, 0)) %>%   # no copper trading = no move
  filter(!is.na(ret)) %>%
  arrange(ticker, date) %>%
  group_by(ticker) %>%
  mutate(tidx = row_number()) %>%   # each firm's own trading-day counter
  ungroup()

ev_all <- events %>%
  select(event_id, use, day0_ref = first_trading_day_TSX) %>%
  cross_join(distinct(panel, ticker)) %>%
  inner_join(panel %>% select(ticker, date, tidx), by = "ticker",
             relationship = "many-to-many") %>%
  filter(date >= day0_ref) %>%
  group_by(event_id, ticker) %>%
  slice_min(date, n = 1) %>%
  ungroup() %>%
  rename(event_day0 = date, tidx0 = tidx)

write_csv(ev_all, file.path(s$out_dir, "event_days_used.csv"))

ev_run <- ev_all %>% filter(use != "exclude")

# ---- 3. Normal-return model for each firm and event ---------------------------
panel_split   <- split(panel, panel$ticker)
model_formula <- if (s$use_copper) ret ~ mkt + cu else ret ~ mkt

fit_one <- function(tk, eid, t0) {
  d <- panel_split[[tk]] %>% mutate(rel = tidx - t0)

  # Days close to OTHER Cobre Panama events are not "normal" days: drop them
  other <- ev_all$tidx0[ev_all$ticker == tk & ev_all$event_id != eid]
  near_other <- if (length(other) > 0 && s$other_event_buffer > 0) {
    apply(abs(outer(d$tidx, other, "-")) <= s$other_event_buffer, 1, any)
  } else {
    rep(FALSE, nrow(d))
  }

  est <- d[d$rel >= s$est_start & d$rel <= s$est_end & !near_other, ]
  if (nrow(est) < s$min_est_obs) {
    if (!s$quiet) message("Skipped ", tk, " / ", eid, ": only ", nrow(est),
                          " estimation days")
    return(NULL)
  }

  m  <- lm(model_formula, data = est)
  co <- coef(m)

  evw <- d[d$rel >= -10 & d$rel <= 10, ]
  evw$ar <- evw$ret - predict(m, newdata = evw)

  list(
    params = tibble(ticker = tk, event_id = eid, n_est = nrow(est),
                    alpha = co[["(Intercept)"]], beta_mkt = co[["mkt"]],
                    gamma_cu = if (s$use_copper) co[["cu"]] else NA_real_,
                    sigma = summary(m)$sigma, r2 = summary(m)$r.squared),
    ar    = tibble(ticker = tk, event_id = eid, rel = evw$rel,
                   date = evw$date, ar = evw$ar),
    resid = tibble(ticker = tk, event_id = eid, date = est$date,
                   resid = residuals(m))
  )
}

fits <- pmap(list(ev_run$ticker, ev_run$event_id, ev_run$tidx0), fit_one) %>%
  compact()

params    <- map_dfr(fits, "params")
ar_all    <- map_dfr(fits, "ar")
resid_all <- map_dfr(fits, "resid")

# ---- 4. Windows table ---------------------------------------------------------
specific <- windows_spec %>% filter(event_id != "default")
default_w <- windows_spec %>% filter(event_id == "default") %>% select(-event_id)
ev_ids <- distinct(ev_run, event_id)

win_tbl <- bind_rows(
  ev_ids %>% filter(!event_id %in% specific$event_id) %>% cross_join(default_w),
  specific %>% semi_join(ev_ids, by = "event_id")
) %>%
  mutate(window = paste0("[", w_start, ",",
                         if_else(w_end > 0, paste0("+", w_end), as.character(w_end)),
                         "]"),
         L = w_end - w_start + 1)

# ---- 5. Firm-level CARs and tests --------------------------------------------
car_firm <- ar_all %>%
  inner_join(win_tbl, by = "event_id", relationship = "many-to-many") %>%
  filter(rel >= w_start, rel <= w_end) %>%
  group_by(ticker, event_id, window, main, w_start, w_end, L) %>%
  summarise(car = sum(ar), n_days = n(), .groups = "drop") %>%
  filter(n_days == L) %>%                      # drop windows with missing days
  left_join(params, by = c("ticker", "event_id")) %>%
  mutate(t_stat = car / (sigma * sqrt(L)),
         p_t    = 2 * pt(-abs(t_stat), df = n_est - if (s$use_copper) 3 else 2))

# SQ test: how unusual is this CAR compared with every L-day sum of residuals
# in the estimation window? Empirical distribution, no normality assumption.
# The +1 terms keep p above zero: with ~170 estimation days the smallest
# two-sided p is about 0.012 ("more extreme than every normal day").
sq_pvalue <- function(tk, eid, car, L) {
  r    <- resid_all$resid[resid_all$ticker == tk & resid_all$event_id == eid]
  sums <- as.numeric(stats::filter(r, rep(1, L), sides = 1))
  sums <- sums[!is.na(sums)]
  n    <- length(sums)
  p_low  <- (sum(sums <= car) + 1) / (n + 1)
  p_high <- (sum(sums >= car) + 1) / (n + 1)
  min(1, 2 * min(p_low, p_high))
}

car_firm <- car_firm %>%
  mutate(p_sq = pmap_dbl(list(ticker, event_id, car, L), sq_pvalue)) %>%
  left_join(groups %>% select(ticker, group), by = "ticker") %>%
  left_join(distinct(ev_run, event_id, use, day0_ref), by = "event_id") %>%
  left_join(exclusions %>% transmute(ticker, event_id, excluded = TRUE,
                                     exclusion_reason = reason),
            by = c("ticker", "event_id")) %>%
  mutate(excluded = replace_na(excluded, FALSE) | str_starts(group, "excluded")) %>%
  relocate(group, .after = ticker) %>%
  arrange(event_id, group, ticker, w_start, w_end)

# ---- 6. Group-level tests ----------------------------------------------------
group_test <- function(df, resid_df) {
  n <- nrow(df)
  L <- df$L[1]
  res <- resid_df %>% filter(ticker %in% df$ticker)

  # Portfolio approach: one equal-weighted portfolio per group. Its residual
  # variance already contains the correlation between the firms.
  port   <- res %>% group_by(date) %>% summarise(r = mean(resid), .groups = "drop")
  car_p  <- mean(df$car)
  t_port <- car_p / (sd(port$r) * sqrt(L))
  p_port <- 2 * pt(-abs(t_port), df = nrow(port) - 1)

  # BMP with Kolari-Pynnonen correction, and sign test (need 2+ firms)
  bmp <- kp <- p_kp <- rbar <- p_sign <- NA_real_
  if (n >= 2) {
    scar <- df$car / (df$sigma * sqrt(L))
    bmp  <- mean(scar) * sqrt(n) / sd(scar)
    wide <- res %>% select(date, ticker, resid) %>%
      pivot_wider(names_from = ticker, values_from = resid)
    cm   <- cor(select(wide, -date), use = "pairwise.complete.obs")
    rbar <- mean(cm[upper.tri(cm)], na.rm = TRUE)
    kp   <- bmp * sqrt((1 - rbar) / (1 + (n - 1) * rbar))
    p_kp <- 2 * pt(-abs(kp), df = n - 1)
    p_sign <- binom.test(sum(df$car > 0), n, 0.5)$p.value
  }

  tibble(n_firms = n, firms = paste(df$ticker, collapse = " "),
         mean_car = car_p, median_car = median(df$car),
         n_positive = sum(df$car > 0),
         t_portfolio = t_port, p_portfolio = p_port,
         avg_resid_corr = rbar, t_bmp = bmp, t_kp = kp, p_kp = p_kp,
         p_sign = p_sign)
}

car_group <- car_firm %>%
  filter(!is.na(group), !excluded) %>%
  group_by(group, event_id, use, window, main) %>%
  group_modify(~ group_test(.x, resid_all %>% filter(event_id == .y$event_id))) %>%
  ungroup() %>%
  arrange(event_id, group, window)

# ---- 7. Save -----------------------------------------------------------------
write_csv(params,    file.path(s$out_dir, "model_params.csv"))
write_csv(ar_all,    file.path(s$out_dir, "abnormal_returns_daily.csv"))
write_csv(car_firm,  file.path(s$out_dir, "car_firm.csv"))
write_csv(car_group, file.path(s$out_dir, "car_group.csv"))

writeLines(c(paste("Run at:", Sys.time()),
             paste("Estimation window:", s$est_start, "to", s$est_end),
             paste("Copper factor:", s$use_copper),
             paste("Market return:", s$market_col),
             paste("Other-event buffer (days):", s$other_event_buffer),
             paste("Firm-event models estimated:", nrow(params)),
             paste("Firm-event exclusions:", nrow(exclusions))),
           file.path(s$out_dir, "run_info.txt"))

if (!s$quiet) {
  core_ids <- unique(ev_run$event_id[ev_run$use == "core"])

  cat("\n=== Day 0 used for each core event (first TSX firm) ===\n")
  ev_run %>% filter(ticker == "FM.TO", use == "core") %>%
    select(event_id, day0_ref, event_day0) %>% print(n = Inf)

  cat("\n=== First Quantum and Franco-Nevada, core events, all windows ===\n")
  car_firm %>%
    filter(ticker %in% c("FM.TO", "FNV.TO"), event_id %in% core_ids) %>%
    transmute(ticker, event_id, window, main,
              car_simple_pct = round(100 * (exp(car) - 1), 1),
              t_stat = round(t_stat, 1), p_sq = round(p_sq, 3)) %>%
    print(n = Inf)

  cat("\n=== Groups, core events, main window ===\n")
  car_group %>%
    filter(event_id %in% core_ids, main) %>%
    transmute(event_id, window, group, n_firms, n_positive,
              mean_car_pct = round(100 * mean_car, 2),
              p_portfolio = round(p_portfolio, 3), p_kp = round(p_kp, 3)) %>%
    print(n = Inf, width = Inf)

  # ---- 8. Figure: CAR paths of FM and FNV around three key events -----------
  event_labels <- c(E2 = "E2: referendum announced (30 Oct 2023)",
                    E6 = "E6: court ruling (day 0) + closure order (day +1), Nov 2023",
                    F6 = "F6: closure recommended (30 Sep 2026)")

  plot_df <- ar_all %>%
    filter(ticker %in% c("FM.TO", "FNV.TO"), event_id %in% names(event_labels),
           rel >= -5, rel <= 10) %>%
    arrange(ticker, event_id, rel) %>%
    group_by(ticker, event_id) %>%
    mutate(car = cumsum(ar)) %>%
    ungroup()

  p <- ggplot(plot_df, aes(rel, 100 * car, colour = ticker)) +
    geom_hline(yintercept = 0, colour = "grey60") +
    geom_vline(xintercept = 0, linetype = "dashed", colour = "grey60") +
    geom_line(linewidth = 0.8) +
    geom_point(size = 1.2) +
    facet_wrap(~ event_id, labeller = as_labeller(event_labels)) +
    labs(x = "Trading days relative to the event (day 0)",
         y = "Cumulative abnormal return, % (log)", colour = NULL,
         title = "First Quantum and Franco-Nevada around key Cobre Panama events",
         subtitle = "Market model with home index and copper, estimated on days -250 to -30") +
    theme_minimal(base_size = 11) +
    theme(legend.position = "bottom")

  ggsave(file.path(s$out_dir, "fig_car_fm_fnv.png"), p,
         width = 12, height = 4.5, dpi = 200)

  message("Done. Results saved in the ", s$out_dir, "/ folder.")
}
