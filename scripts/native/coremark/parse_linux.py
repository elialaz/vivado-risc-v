#!/usr/bin/env python3
"""Append LINUX_CM lines from the UART log (after --offset) to the CoreMark CSV.
CoreMark/MHz = Iterations/Sec / clock MHz."""
import argparse, csv, os, re, time
ap = argparse.ArgumentParser()
ap.add_argument("--uart-log", required=True)
ap.add_argument("--offset", type=int, default=0)
ap.add_argument("--csv", required=True)
ap.add_argument("--board-config", required=True)
ap.add_argument("--mhz", type=float, required=True)
a = ap.parse_args()
with open(a.uart_log, "rb") as f:
    f.seek(a.offset)
    data = f.read().decode(errors="replace")
rx = re.compile(r"LINUX_CM core=(\S+) mode=(\S+) run=(\d+) ips=([\d.]*) validated=(\d+)")
new = not os.path.exists(a.csv)
with open(a.csv, "a", newline="") as fc:
    w = csv.writer(fc)
    if new:
        w.writerow(["time", "board_config", "env", "core", "mode", "run", "iterations",
                    "cycles", "coremark_per_mhz", "validated", "note"])
    for core, mode, run, ips, ok in rx.findall(data):
        score = "%.3f" % (float(ips) / a.mhz) if ips else ""
        print(f"{core}-{mode} run {run}: {score} CoreMark/MHz (linux, validated={ok == '1'})")
        w.writerow([time.strftime("%Y-%m-%d %H:%M:%S"), a.board_config, "linux", core, mode, run,
                    4000, "", score, ok == "1", f"ips={ips} @ {a.mhz} MHz"])
