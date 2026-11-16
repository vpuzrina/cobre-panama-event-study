# Pricing a mine closure: Cobre Panamá, 2023–2026

An event study of how the stock market priced the shutdown of Panama's Cobre Panamá copper mine, for the mine's owner and for other firms along the copper value chain.

**Report:** [report/cobre_panama_report.pdf](report/cobre_panama_report.pdf)

## Question

When a government takes a large mine off the market, who loses and does anyone gain? Cobre Panamá produced about 1.5% of world copper in 2022. I estimate abnormal stock returns for 15 listed firms around five political and legal events between October 2023 and September 2026: the mine's owner (First Quantum), the holder of a stream on its output (Franco-Nevada), rival copper miners and copper smelters.

## Main results

| | First Quantum | Franco-Nevada |
| --- | --- | --- |
| Referendum announced, 30 Oct 2023, CAR [0, +1] | −43.6% (about −USD 6.1bn) | −12.1% (about −USD 3.1bn) |
| Court ruling and closure order, 28–29 Nov 2023 | −12.1% | −2.7% (not significant) |
| Closure recommended, 30 Sep 2026 | −12.8% | −2.5% (not significant) |

- First Quantum's losses hold across five model specifications and a placebo test on 639 days without Cobre Panamá news.
- On the 2023 closure, the court ruling itself barely moved the stock (−1.8%); the president's closure order that evening cost another 10.6% the next day.
- Franco-Nevada's market loss on the referendum was about 2.6 times the USD 1.17bn it later wrote off.
- Rival miners and smelters show no reaction that survives the placebo test.

## Method

- Market model with the firm's home-market index and COMEX copper futures, estimated on trading days −250 to −30 before each event.
- Single firms: t-test and the SQ test of Gelbach, Helland and Klick (2013).
- Groups: equal-weighted portfolio test and the BMP test with the Kolari and Pynnönen (2010) correction for event-date clustering.
- Robustness: no copper factor, world index, shorter estimation window, no buffer around other events, placebo dates.
- Event dates were checked against news timestamps; firm-event pairs with other news on the same days are excluded (see `exclusions.csv` and `notes/confounders.md`).

## Repository

| File | What it does |
| --- | --- |
| `01_download_data.R` | Downloads daily prices from Yahoo Finance and builds the returns panel (`data/`) |
| `02_event_study.R` | Abnormal returns, CARs and tests (`results/`) |
| `03_robustness.R` | Alternative specifications and placebo test (`results_robustness/`) |
| `04_dollar_losses.R` | Converts the main CARs into market value |
| `events.csv` | Events, day-0 dates, sources and notes |
| `companies.csv` | Firms, groups, benchmarks, Latin America output shares with sources |
| `exclusions.csv` | Firm-event pairs left out of group tests, with reasons |
| `dollar_inputs.csv` | Shares outstanding and exchange rates, with sources |
| `notes/decisions.md` | Log of research decisions and what each changed |
| `notes/confounders.md` | News check around every event date |
| `report/` | LaTeX source, figures and PDF of the report |

## How to run

Requires R with `tidyverse` and `tidyquant`:

```r
install.packages(c("tidyverse", "tidyquant"))
```

From the repository folder:

```r
source("01_download_data.R")
source("02_event_study.R")
source("03_robustness.R")
source("04_dollar_losses.R")
```

Price data are not included in the repository, because Yahoo Finance's terms do not allow redistribution. The first script downloads them again, so results may differ slightly if Yahoo revises its adjusted prices.

## Author

Varvara Puzrina, Boston University (Economics and Computer Science). Independent research project, 2026.
