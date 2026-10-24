#!/usr/bin/env python3
"""Run bare-metal CoreMark images on the Genesys 2 board, several times each.

The board UART must be logged to --uart-log by a separate logger. Each run
loads the image over JTAG, starts it at its load address, and waits for the
COREMARK_RESULT line on the UART. Results are appended to --csv.

  xsdb  backend: CVA6 (debug-module system bus load) and Rocket/BOOM.
  grmon backend: NOEL-V (GRMON AHBJTAG; hw_server must not be running).
"""
import argparse
import csv
import os
import re
import subprocess
import sys
import tempfile
import time

XSDB = "/tools/Xilinx/Vivado/2024.1/bin/xsdb"
GRMON_DIR = os.path.expanduser(
    "~/Projects/Softcore/noel/sw/grmon-eval-4.1.2-dl/grmon-eval-4.1.2/linux")
JTAG_SERIAL = "200300BB2DF7"

RESULT = re.compile(rb"COREMARK_RESULT core=(\S+) mode=(\S+) iterations=(\d+) "
                    rb"cycles=(\d+) coremark_per_mhz=([\d.]+)")
TRAP = re.compile(rb"COREMARK_TRAP [^\r\n]*")
VALID = re.compile(rb"Correct operation validated")
ERROR = re.compile(rb"ERROR![^\r\n]*")


def xsdb_script(binfile, addr, sba):
    load_target = 'targets -set -filter {name =~ "RISC-V"}' if sba else \
        'targets -set -filter {name =~ "Hart #0*"}'
    return f"""
connect -url tcp:localhost:3121
targets -set -filter {{name =~ "Hart #0*"}}
catch {{stop}}
{load_target}
dow -data {binfile} {addr}
targets -set -filter {{name =~ "Hart #0*"}}
rwr priv 3
rwr csr mie 0
rwr csr mstatus 0x1800
rwr csr satp 0
rwr pc {addr}
con
puts XSDB_STARTED
"""


def grmon_script(elf, addr):
    return f"""
load {elf}
puts "GRMON_LOADED"
run {addr}
puts "GRMON_RUN_RETURNED"
exit
"""


def elf_entry(elf):
    out = subprocess.run(["riscv64-linux-gnu-readelf", "-h", elf], capture_output=True,
                         text=True, check=True).stdout
    return re.search(r"Entry point address:\s+(0x[0-9a-f]+)", out).group(1)


def start_run(args, elf, workdir):
    addr = args.addr or elf_entry(elf)
    if args.backend == "xsdb":
        binfile = os.path.join(workdir, os.path.basename(elf) + ".bin")
        subprocess.run(["riscv64-linux-gnu-objcopy", "-O", "binary", elf, binfile], check=True)
        tcl = os.path.join(workdir, "run.tcl")
        with open(tcl, "w") as f:
            f.write(xsdb_script(binfile, addr, args.sba))
        out = subprocess.run([XSDB, tcl], capture_output=True, text=True, timeout=120)
        if "XSDB_STARTED" not in out.stdout:
            raise RuntimeError("xsdb failed: " + (out.stdout + out.stderr)[-800:])
        return None
    tcl = os.path.join(workdir, "run.tcl")
    with open(tcl, "w") as f:
        f.write(grmon_script(elf, addr))
    env = dict(os.environ, LD_LIBRARY_PATH=os.path.join(GRMON_DIR, "lib64"))
    # GRMON's `run` returns when the image ends with ebreak; keep it attached
    # until then (detaching mid-run can leave the debug state behind).
    return subprocess.Popen([os.path.join(GRMON_DIR, "bin64", "grmon"), "-digilent",
                             "-jtagserial", JTAG_SERIAL, "-ni", "-nb", "-c", tcl],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env)


def wait_result(log, offset, timeout):
    deadline = time.time() + timeout
    while time.time() < deadline:
        with open(log, "rb") as f:
            f.seek(offset)
            data = f.read()
        m = RESULT.search(data)
        t = TRAP.search(data)
        if t:
            return None, data, t.group(0).decode(errors="replace")
        if m:
            # The validation line is printed after the result by core_main.
            end = time.time() + 5
            while time.time() < end and b"COREMARK_DONE" not in data:
                time.sleep(0.5)
                with open(log, "rb") as f:
                    f.seek(offset)
                    data = f.read()
            return m, data, None
        time.sleep(1)
    return None, b"", "timeout"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--backend", choices=["xsdb", "grmon"], required=True)
    ap.add_argument("--board-config", required=True, help="CONFIG name, recorded in the CSV")
    ap.add_argument("--uart-log", required=True)
    ap.add_argument("--csv", required=True)
    ap.add_argument("--runs", type=int, default=5)
    ap.add_argument("--addr", default=None, help="load/entry address (default: ELF entry)")
    ap.add_argument("--no-sba", dest="sba", action="store_false",
                    help="xsdb: load through the hart instead of the system bus")
    ap.add_argument("--timeout", type=int, default=180)
    ap.add_argument("elfs", nargs="+")
    args = ap.parse_args()

    new = not os.path.exists(args.csv)
    with open(args.csv, "a", newline="") as fcsv, tempfile.TemporaryDirectory() as wd:
        w = csv.writer(fcsv)
        if new:
            w.writerow(["time", "board_config", "env", "core", "mode", "run", "iterations",
                        "cycles", "coremark_per_mhz", "validated", "note"])
        for elf in args.elfs:
            for run in range(1, args.runs + 1):
                offset = os.path.getsize(args.uart_log)
                proc = start_run(args, elf, wd)
                m, data, err = wait_result(args.uart_log, offset, args.timeout)
                if proc is not None:
                    try:
                        proc.wait(timeout=30)
                    except subprocess.TimeoutExpired:
                        proc.kill()
                stamp = time.strftime("%Y-%m-%d %H:%M:%S")
                if m is None:
                    print(f"{os.path.basename(elf)} run {run}: FAILED ({err})", flush=True)
                    w.writerow([stamp, args.board_config, "baremetal", "", os.path.basename(elf),
                                run, "", "", "", "", err])
                    fcsv.flush()
                    continue
                core, mode, it, cyc, score = (g.decode() for g in m.groups())
                valid = bool(VALID.search(data)) and not ERROR.search(data)
                print(f"{core}-{mode} run {run}: {score} CoreMark/MHz "
                      f"({cyc} cycles, validated={valid})", flush=True)
                w.writerow([stamp, args.board_config, "baremetal", core, mode, run, it, cyc,
                            score, valid, ""])
                fcsv.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
