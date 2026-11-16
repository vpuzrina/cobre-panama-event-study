# =============================================================================
# Cobre Panama event study - Step 4: CARs in dollars
#
# Turns the main-window CARs of First Quantum and Franco-Nevada into market
# value gained or lost, and sets them next to the accounting and legal numbers.
#
#   value change = market cap on day -1 x (exp(CAR) - 1)
#   market cap   = shares outstanding x closing price on day -1
#
# Input:  results/car_firm.csv (from 02), data/prices_raw.csv (from 01),
#         dollar_inputs.csv (shares outstanding and USD/CAD, with sources)
# Output: results/dollar_losses.csv
#
# Caveats:
# - Prices are Yahoo "adjusted" closes. For FM they equal the actual closes
#   (checked against press reports). For FNV the 2023 prices are a few percent
#   below the actual closes because of later dividends, so FNV's 2023 dollar
#   figures are slightly understated.
# - A CAR is the reaction to the news only. It is not a damages estimate: the
#   price already reflects what investors expected to recover in arbitration.
# =============================================================================

library(tidyverse)
options(readr.num_threads = 1)
rd <- function(p) read_csv(p, show_col_types = FALSE, lazy = FALSE, num_threads = 1)

car_firm <- rd("results/car_firm.csv")
prices   <- rd("data/prices_raw.csv")
inputs   <- rd("dollar_inputs.csv")

out <- inputs %>%
  left_join(prices %>% select(ticker = symbol, day_minus_1 = date, price_cad = adjusted),
            by = c("ticker", "day_minus_1")) %>%
  left_join(car_firm %>% filter(main) %>%
              select(ticker, event_id, window, car, p_sq),
            by = c("ticker", "event_id")) %>%
  mutate(cap_cad_bn   = price_cad * shares_millions / 1000,
         cap_usd_bn   = cap_cad_bn / usdcad,
         car_simple   = exp(car) - 1,
         change_usd_bn = cap_usd_bn * car_simple,
         significant_10pct = p_sq < 0.10)

write_csv(out, "results/dollar_losses.csv")

cat("\n=== Market value change in the main event window ===\n")
out %>%
  transmute(ticker, event_id, window,
            cap_usd_bn = round(cap_usd_bn, 2),
            car_pct = round(100 * car_simple, 1),
            change_usd_bn = round(change_usd_bn, 2),
            p_sq = round(p_sq, 3)) %>%
  print(n = Inf)

cat("\n=== 2023 closure events combined (E2 + E3 + E6) ===\n")
out %>%
  filter(event_id %in% c("E2", "E3", "E6")) %>%
  group_by(ticker) %>%
  summarise(total_change_usd_bn = round(sum(change_usd_bn), 2)) %>%
  print()

cat("\nFor comparison (sources in the report):\n",
    "- Franco-Nevada impairment of the Cobre Panama stream, Q4 2023: US$1.17bn\n",
    "- Franco-Nevada stream revenue from Cobre Panama in 2023: US$248.9m\n",
    "- First Quantum arbitration claim: about US$20bn (suspended)\n",
    "- Franco-Nevada arbitration claim: at least US$5bn (suspended)\n")
