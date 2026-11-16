# =============================================================================
# Cobre Panama event study - Step 1: download prices and build a returns panel
# Version 2 (29 Oct 2026): adds the world index for robustness and the `use`
# column from events.csv (core / exploratory / context / exclude).
#
# Input:  events.csv, companies.csv  (same folder as this script)
# Output: data/prices_raw.csv      daily adjusted prices for every ticker
#         data/returns_panel.csv   stock return + home index + world index
#                                  + copper, one row per ticker per day
#         data/event_days.csv      the actual trading day of each event
#                                  for each ticker (exchanges differ)
#         data/download_log.csv    which tickers downloaded, how many rows
#         data/manual_check.csv    5 prices to compare with a second source
#
# Run once:  install.packages(c("tidyverse", "tidyquant"))
# =============================================================================

library(tidyverse)
library(tidyquant)

# ---- Settings ---------------------------------------------------------------
# Estimation window is days -250 to -30 before the first event (Oct 2023),
# so the data must start well before Oct 2022.
start_date <- as.Date("2022-08-01")
end_date   <- Sys.Date()

copper_ticker <- "HG=F"
world_ticker  <- "ACWI"   # iShares MSCI ACWI ETF, proxy for the world index
                          # (robustness check only; it trades in New York hours)

dir.create("data", showWarnings = FALSE)

# ---- 1. Read inputs ---------------------------------------------------------
companies <- read_csv("companies.csv", show_col_types = FALSE)
events    <- read_csv("events.csv",    show_col_types = FALSE) %>%
  filter(!is.na(first_trading_day_TSX))       # drops the TC/RC context row C1

stocks <- companies %>% filter(ticker_yahoo != copper_ticker)

all_tickers <- unique(c(stocks$ticker_yahoo,
                        stocks$benchmark_index_yahoo,
                        copper_ticker,
                        world_ticker))

# ---- 2. Download prices (one ticker at a time so one failure doesn't stop all)
download_one <- function(tk) {
  message("Downloading ", tk, " ...")
  out <- tryCatch(
    tq_get(tk, get = "stock.prices", from = start_date, to = end_date),
    error = function(e) NULL
  )
  if (is.null(out) || !is.data.frame(out) || nrow(out) == 0) {
    message("   !! failed: ", tk)
    return(tibble())
  }
  out %>% select(symbol, date, adjusted)
}

prices <- map_dfr(all_tickers, download_one)

log_tbl <- tibble(symbol = all_tickers) %>%
  left_join(prices %>% count(symbol, name = "n_rows"), by = "symbol") %>%
  mutate(n_rows = replace_na(n_rows, 0),
         status = if_else(n_rows > 0, "ok", "FAILED - check ticker in Yahoo"))

write_csv(prices,  "data/prices_raw.csv")
write_csv(log_tbl, "data/download_log.csv")
print(log_tbl, n = Inf)

# ---- 3. Daily log returns ---------------------------------------------------
# Returns are unit-free, so currencies (and LSE prices in pence) don't matter.
returns <- prices %>%
  filter(!is.na(adjusted)) %>%
  arrange(symbol, date) %>%
  group_by(symbol) %>%
  mutate(ret = log(adjusted / lag(adjusted))) %>%
  ungroup() %>%
  filter(!is.na(ret))

copper_ret <- returns %>% filter(symbol == copper_ticker) %>%
  select(date, copper_ret = ret)
world_ret  <- returns %>% filter(symbol == world_ticker) %>%
  select(date, world_ret = ret)

# ---- 4. Panel: each stock with its own benchmark on the same date -----------
# inner_join keeps only days when both the stock and its index traded
# (handles different national holidays automatically)
returns_panel <- stocks %>%
  select(ticker = ticker_yahoo, company, group, exchange, benchmark_index_yahoo) %>%
  inner_join(returns %>% select(ticker = symbol, date, ret), by = "ticker") %>%
  inner_join(returns %>% select(benchmark_index_yahoo = symbol, date, mkt_ret = ret),
             by = c("benchmark_index_yahoo", "date")) %>%
  left_join(copper_ret, by = "date") %>%       # copper can be NA on some days
  left_join(world_ret,  by = "date") %>%
  arrange(ticker, date)

write_csv(returns_panel, "data/returns_panel.csv")

# ---- 5. Event day for each ticker -------------------------------------------
# Day 0 = first day ON OR AFTER the TSX event day when that stock traded.
# Asian and European markets close before Toronto opens, so for them news from
# the North American day often shows up only the next day: the analysis uses
# windows like [0, +1] and [-1, +1], not day 0 alone.
trading_days <- returns_panel %>% distinct(ticker, date)

event_days <- events %>%
  select(event_id, period, use, first_trading_day_TSX) %>%
  cross_join(stocks %>% select(ticker = ticker_yahoo)) %>%
  left_join(trading_days, by = "ticker", relationship = "many-to-many") %>%
  filter(date >= first_trading_day_TSX) %>%
  group_by(event_id, ticker) %>%
  slice_min(date, n = 1) %>%
  ungroup() %>%
  rename(event_day0 = date)

write_csv(event_days, "data/event_days.csv")

# ---- 6. Sanity checks -------------------------------------------------------
# (a) Big negative FM.TO returns expected on 2023-10-30/31 and 2026-09-30
returns_panel %>%
  filter(ticker %in% c("FM.TO", "FNV.TO"),
         date %in% as.Date(c("2023-10-30", "2023-10-31", "2023-11-03",
                             "2023-11-28", "2026-09-30"))) %>%
  mutate(ret_pct = round(100 * (exp(ret) - 1), 1)) %>%
  select(ticker, date, ret_pct) %>%
  print(n = Inf)

# (b) Coverage per ticker (e.g. TECK after the merger, Tongling)
returns_panel %>%
  group_by(ticker) %>%
  summarise(first_day = min(date), last_day = max(date), n_days = n(),
            zero_ret_share = round(mean(ret == 0), 3)) %>%   # thin trading
  print(n = Inf)

# (c) Five prices to compare by hand with Google Finance or the exchange site
manual_check <- prices %>%
  filter(symbol %in% c("FM.TO", "FNV.TO", "FCX", "NDA.DE", "0358.HK"),
         date == as.Date("2023-10-30") | date == as.Date("2023-10-31")) %>%
  group_by(symbol) %>% slice_min(date, n = 1) %>% ungroup() %>%
  mutate(your_second_source = NA_real_, match = NA)
write_csv(manual_check, "data/manual_check.csv")
print(manual_check)

message("Done. Files saved in the data/ folder.")
