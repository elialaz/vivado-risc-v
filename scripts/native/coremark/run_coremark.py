#!/usr/bin/env python3
"""Run bare-metal CoreMark images on the Genesys 2 board, several times each.

The board UART must be logged to --uart-log by a separate logger. Each run
loads the image over JTAG, starts it at its load address, and waits for the
COREMARK_RESULT line on the UART. Results are appended to --csv.

  xsdb  backend: CVA6 (debug-module system bus load) and Rocket/BOOM.
  grmon backend: NOEL-V (GRMON AHBJTAG; hw_server must not be running).
  uboot backend: cores without a usable debugger (Shuttle). Images built
                 with -DSMODE are sent to U-Boot with `loady` (YMODEM, lrzsz
                 `sb`) and started with `go`; they return to the prompt. This
                 backend opens the UART itself and appends to --uart-log, so
                 stop any other UART logger first. With --bitstream the FPGA
                 is programmed first and autoboot is stopped.
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

UART_PORT = "/dev/serial/by-id/usb-FTDI_FT232R_USB_UART_AV0KRWIT-if00-port0"

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


class UBoot:
    """U-Boot console on the board UART, logged to the UART log file."""

    def __init__(self, port, log):
        import serial
        self.ser = serial.Serial(port, 115200, timeout=0.1)
        self.log = open(log, "ab", buffering=0)
        self.buf = b""

    def send(self, text):
        for ch in text.encode():
            self.ser.write(bytes([ch]))
            time.sleep(0.002)

    def expect(self, pattern, timeout):
        deadline = time.time() + timeout
        while time.time() < deadline:
            data = self.ser.read(4096)
            if data:
                self.log.write(data)
                self.buf += data
                i = self.buf.find(pattern)
                if i >= 0:
                    self.buf = self.buf[i + len(pattern):]
                    return True
        return False

    def drain(self):
        """Log and drop whatever the board already sent."""
        while True:
            data = self.ser.read(4096)
            if not data:
                break
            self.log.write(data)
        self.buf = b""

    def prompt(self, timeout=90):
        # Ctrl-C, not Enter: an empty line makes U-Boot repeat the last
        # command, which would start the previous image again with `go`.
        # The timeout covers an image that is still running.
        self.drain()
        self.send("\x03")
        if not self.expect(b"=> ", timeout):
            raise RuntimeError("no U-Boot prompt")
        self.drain()

    def program(self, bitstream):
        tcl = f"""connect -url tcp:localhost:3121
targets -set -filter {{name =~ "xc7k325t*"}}
fpga -file {bitstream}
puts PROGRAMMED
"""
        with tempfile.NamedTemporaryFile("w", suffix=".tcl", delete=False) as f:
            f.write(tcl)
        out = subprocess.run([XSDB, f.name], capture_output=True, text=True, timeout=180)
        os.unlink(f.name)
        if "PROGRAMMED" not in out.stdout:
            raise RuntimeError("programming failed: " + (out.stdout + out.stderr)[-800:])
        self.buf = b""
        if not self.expect(b"Hit any key", 180):
            raise RuntimeError("U-Boot autoboot prompt not seen")
        self.send(" ")
        if not self.expect(b"=> ", 10):
            raise RuntimeError("could not stop autoboot")

    def load_and_go(self, binfile, addr, timeout):
        self.prompt()
        self.send(f"loady {addr}\r")
        if not self.expect(b"Ready for binary", 10):
            raise RuntimeError("loady did not start")
        import fcntl
        fd = self.ser.fileno()
        flags = fcntl.fcntl(fd, fcntl.F_GETFL)
        fcntl.fcntl(fd, fcntl.F_SETFL, flags & ~os.O_NONBLOCK)  # sb needs blocking I/O
        try:
            r = subprocess.run(["sb", "-q", binfile], stdin=fd, stdout=fd,
                               stderr=subprocess.PIPE, timeout=300)
        finally:
            fcntl.fcntl(fd, fcntl.F_SETFL, flags)
        if r.returncode != 0:
            raise RuntimeError(f"YMODEM send failed (rc={r.returncode}): "
                               + r.stderr.decode(errors="replace"))
        if not self.expect(b"=> ", 20):
            raise RuntimeError("no prompt after loady")
        self.send(f"go {addr}\r")
        if not self.expect(b"COREMARK_DONE", timeout):
            raise RuntimeError("image did not finish")
        self.expect(b"=> ", 10)


def elf_entry(elf):
    out = subprocess.run(["riscv64-linux-gnu-readelf", "-h", elf], capture_output=True,
                         text=True, check=True).stdout
    return re.search(r"Entry point address:\s+(0x[0-9a-f]+)", out).group(1)


def start_run(args, elf, workdir):
    addr = args.addr or elf_entry(elf)
    if args.backend == "uboot":
        binfile = os.path.join(workdir, os.path.basename(elf) + ".bin")
        subprocess.run(["riscv64-linux-gnu-objcopy", "-O", "binary", elf, binfile], check=True)
        args.uboot.load_and_go(binfile, addr, args.timeout)
        return None
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
    ap.add_argument("--backend", choices=["xsdb", "grmon", "uboot"], required=True)
    ap.add_argument("--board-config", required=True, help="CONFIG name, recorded in the CSV")
    ap.add_argument("--uart-log", required=True)
    ap.add_argument("--csv", required=True)
    ap.add_argument("--runs", type=int, default=5)
    ap.add_argument("--addr", default=None, help="load/entry address (default: ELF entry)")
    ap.add_argument("--no-sba", dest="sba", action="store_false",
                    help="xsdb: load through the hart instead of the system bus")
    ap.add_argument("--timeout", type=int, default=180)
    ap.add_argument("--uart-port", default=UART_PORT, help="uboot: board UART device")
    ap.add_argument("--bitstream", default=None,
                    help="uboot: program this bitstream first and stop autoboot")
    ap.add_argument("elfs", nargs="+")
    args = ap.parse_args()
    if args.backend == "uboot":
        args.uboot = UBoot(args.uart_port, args.uart_log)
        if args.bitstream:
            args.uboot.program(args.bitstream)

    new = not os.path.exists(args.csv)
    with open(args.csv, "a", newline="") as fcsv, tempfile.TemporaryDirectory() as wd:
        w = csv.writer(fcsv)
        if new:
            w.writerow(["time", "board_config", "env", "core", "mode", "run", "iterations",
                        "cycles", "coremark_per_mhz", "validated", "note"])
        for elf in args.elfs:
            for run in range(1, args.runs + 1):
                offset = os.path.getsize(args.uart_log)
                try:
                    proc = start_run(args, elf, wd)
                    m, data, err = wait_result(args.uart_log, offset, args.timeout)
                except RuntimeError as e:
                    if args.backend != "uboot":
                        raise
                    proc, m, data, err = None, None, b"", str(e)
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
                want = os.path.basename(elf).rsplit(".", 1)[0]
                if f"{core}-{mode}" != want:
                    print(f"{want} run {run}: FAILED (result is from {core}-{mode})", flush=True)
                    w.writerow([stamp, args.board_config, "baremetal", core, mode, run, it, cyc,
                                score, "", f"wrong image, expected {want}"])
                    fcsv.flush()
                    continue
                valid = bool(VALID.search(data)) and not ERROR.search(data)
                print(f"{core}-{mode} run {run}: {score} CoreMark/MHz "
                      f"({cyc} cycles, validated={valid})", flush=True)
                w.writerow([stamp, args.board_config, "baremetal", core, mode, run, it, cyc,
                            score, valid, ""])
                fcsv.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
