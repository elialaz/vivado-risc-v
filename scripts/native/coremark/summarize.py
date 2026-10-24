#!/usr/bin/env python3
"""Best CoreMark/MHz per core from the CoreMark CSV (validated runs only).

Columns: bare-metal and Linux, baseline build and best optimized build
(the best of opt/opt2/opt3/opt4), with the run count and spread of the best mode.
"""
import argparse
import csv
from collections import defaultdict


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("csv")
    ap.add_argument("--markdown", action="store_true")
    a = ap.parse_args()

    scores = defaultdict(list)  # (config, env, mode) -> [score]
    for r in csv.DictReader(open(a.csv)):
        if r["validated"] != "True" or not r["coremark_per_mhz"]:
            continue
        scores[(r["board_config"], r["env"], r["mode"])].append(float(r["coremark_per_mhz"]))

    configs = sorted({k[0] for k in scores})
    rows = []
    for c in configs:
        row = [c]
        for env in ("baremetal", "linux"):
            base = scores.get((c, env, "base"), [])
            opt = {m: scores.get((c, env, m), []) for m in ("opt", "opt2", "opt3", "opt4")}
            best_opt_mode = max(opt, key=lambda m: max(opt[m]) if opt[m] else 0)
            row.append(f"{max(base):.3f} ({len(base)})" if base else "-")
            o = opt[best_opt_mode]
            row.append(f"{max(o):.3f} ({len(o)}, {best_opt_mode})" if o else "-")
        rows.append(row)

    hdr = ["CONFIG", "bare-metal base", "bare-metal opt", "Linux base", "Linux opt"]
    if a.markdown:
        print("| " + " | ".join(hdr) + " |")
        print("|" + "---|" * len(hdr))
        for r in rows:
            print("| " + " | ".join(r) + " |")
    else:
        w = [max(len(x) for x in col) for col in zip(hdr, *rows)]
        for r in [hdr] + rows:
            print("  ".join(x.ljust(n) for x, n in zip(r, w)))


if __name__ == "__main__":
    main()
