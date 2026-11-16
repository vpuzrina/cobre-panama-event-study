# Decisions log - Cobre Panamá event study

One entry per decision: what I chose, the alternatives, why, and whether it changed the result.

## 2026-10-29 - Research design accepted

Defaults taken from the design draft. I can still change any of these before the first results.

| # | Decision | Alternatives | Why | Changed result? |
|---|---|---|---|---|
| 1 | Research question as in the design doc | - | (rewrite in my own words) | - |
| 2 | Rivals split by share of copper output from Latin America (>50%) | By headquarters; no split | Freeport and Hudbay are North American companies that mine mostly in Peru/Chile | not yet run |
| 3 | E1 (Law 406 signed) is context only | Core event with wide window | Good and bad news in the same window, sign unclear | not yet run |
| 4 | Estimation window -250 to -30; -120 to -30 as robustness | -120 as main | Longer window is more stable | not yet run |
| 5 | Teck kept for 2023 events; dropped for 2026 if data missing | Drop entirely | Keeps the 2023 rival sample larger | Resolved 2026-10-30: data through 2026-10-29, kept for all events |
| 6 | Tongling kept only if download is clean | Always keep / always drop | Chinese A-share data on Yahoo is unreliable | Resolved 2026-10-30: downloaded cleanly, kept |
| 7 | Panama sovereign bonds out of scope | Add as fourth asset | Harder data, overlapping news (canal drought, 2024 election) | - |
| 8 | Expected signs as in the hypothesis table | - | Fixed before seeing any returns | - |
| 9 | F5 (restart preparations) excluded | Keep with a flag | Same day as Q2 earnings release | not yet run |

## Next entries

## 2026-10-30 - Data downloaded and checked

- All 25 tickers downloaded with status ok (15 stocks, 9 home indices, ACWI, copper futures), including Tongling (000630.SZ) and the Shenzhen index (399001.SZ). Data runs from Aug 2022 to 2026-10-29.
- Thin trading is not a problem so far: the share of zero-return days is at most about 2% per stock (0 for FM.TO).
- Daily returns cross-checked with Stooq (an independent source) for FCX, NDA.DE and 0358.HK on 2023-10-30: +1.10%, +0.03%, +2.56%, identical to 0.01 pp. Price levels differ by 4-12% because Yahoo's adjusted prices include later dividends; this does not affect returns.
- FM.TO and FNV.TO returns match press reports: FM -28.5% on 2023-10-30 (Bloomberg: up to -31% intraday), FM -15.3% and FNV -3.8% on 2026-09-30 (The Assayer).
- Raw-return observations to keep in mind (not abnormal returns yet): FM fell -28.5% and -19.7% on Oct 30-31, 2023 (about -43% over two days), so the reaction to E2 spans two days and [0, +1] is needed. FM moved only -0.8% on the Supreme Court day (2023-11-28), which supports the wide [-5, +5] window for E6.


## 2026-10-30 - Latin America split for rival miners (decision 2 implemented)

- latam_share added to companies.csv from FY2023 reports (pre-shock exposure): SCCO 1.00, ANTO.L 1.00, LUN.TO 0.96, HBM.TO 0.76, TECK 0.67 -> "Latin America" (5 firms); FCX 0.29, IVN.TO 0.00 -> "other" (2 firms). Sources in the latam_source column.
- Why FY2023 and not the latest year: the main events are in Oct-Nov 2023, so exposure is measured as investors saw it then.
- Caveat: the "other" group has only 2 firms, so its group tests have very low power.

## 2026-10-30 - Event timing, confounders, robustness (scripts v2)

Decisions:
- E6 split (my choice: option A). The court ruled during TSX hours on 28 Nov (day 0); the president announced the closure after the close (day +1). Implemented as one event with separate windows: [0,0] = ruling, [+1,+1] = closure order, [0,+1] = both (main), [-5,+1] = with the week of deliberations. Asian firms see both on 29 Nov, so the split works only for North American listings.
- Day 0 corrections from the confounder scan (details and sources in confounders.md): E3 moved to 2023-11-02 (Assembly vote was Thursday 2 Nov); F2 moved to 2026-02-10 with window [0,0] only; F4 reference date 2026-07-01 so NYSE names get day 0 = 1 Jul (TSX closed for Canada Day). Backups of the old files: events_backup_2026-10-30.csv, companies_backup_2026-10-30.csv.
- Firm-event exclusions (exclusions.csv, left out of group tests): LUN-E3, TECK-E4, IVN-F1, HBM-F1, FCX/SCCO/TECK-F3, ANTO-F6. Reasons in the file.
- Jiangxi Copper (0358.HK) removed from the smelter group: it owns ~18.5% of First Quantum, so it is directly exposed, not a peer.

What changed in the results:
- The odd E3 result for Latin American rivals (-2.4%) disappeared after the day-0 fix (+0.2%). It was a timing error, not a finding.
- FM: E2 -43.6%, E6 -12.1%, F6 -12.8% (simple %, window [0,+1]) are significant in all 5 runs (main, no copper, world index, short estimation window, no buffer) and in the placebo test (p < 0.01). E3 rebound +7.8% is significant in 4 of 5 runs.
- FNV: E2 -12.1% robust; E6 and F6 small (-2.7%, -2.5%) and mostly not significant.
- Rivals on E2: -2.9% (Latin America) and -3.8% (other). Kolari-Pynnonen said significant, but the placebo test says such moves happen on ~11-16% of ordinary days. No robust evidence of either a competitive or a contagion effect.
- Smelters: no significant reaction to any core event.
