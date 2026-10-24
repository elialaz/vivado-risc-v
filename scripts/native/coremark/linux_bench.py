#!/usr/bin/env python3
"""Drive the Linux CoreMark runs over the board console.

Waits for the Debian login prompt in --uart-log (after --offset), logs in as
root, fetches and runs linux-run.sh from the host HTTP server, waits for
LINUX_CM_DONE and appends the results to --csv via parse_linux.py.
Console input goes through the logger's command file (--uart-cmd).
"""
import argparse
import os
import subprocess
import sys
import time


def wait_for(log, offset, needle, timeout):
    deadline = time.time() + timeout
    while time.time() < deadline:
        with open(log, "rb") as f:
            f.seek(offset)
            if needle in f.read():
                return True
        time.sleep(3)
    return False


def send(cmdfile, text):
    with open(cmdfile, "a") as f:
        f.write(text)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--uart-log", required=True)
    ap.add_argument("--uart-cmd", required=True)
    ap.add_argument("--offset", type=int, required=True)
    ap.add_argument("--csv", required=True)
    ap.add_argument("--board-config", required=True)
    ap.add_argument("--core", required=True)
    ap.add_argument("--flavour", default="zb")
    ap.add_argument("--mhz", type=float, required=True)
    ap.add_argument("--runs", type=int, default=5)
    ap.add_argument("--host", default="192.168.6.72:8000")
    ap.add_argument("--boot-timeout", type=int, default=3600)
    ap.add_argument("--logged-in", action="store_true", help="shell prompt already open")
    a = ap.parse_args()

    if a.logged_in:
        return run_bench(a)
    if not wait_for(a.uart_log, a.offset, b"login:", a.boot_timeout):
        print("no login prompt", flush=True)
        return 1
    time.sleep(5)
    off = os.path.getsize(a.uart_log)
    send(a.uart_cmd, "root\n")
    if not wait_for(a.uart_log, off, b"Password:", 300):
        print("no password prompt", flush=True)
        return 1
    send(a.uart_cmd, "root\n")
    if not wait_for(a.uart_log, off, b"root@", 600):
        print("login failed", flush=True)
        return 1
    time.sleep(3)
    return run_bench(a)


def run_bench(a):
    run_off = os.path.getsize(a.uart_log)
    # The Debian image has python3 but no wget/curl.
    fetch = (f"python3 -c \"import sys,urllib.request as u;"
             f"sys.stdout.buffer.write(u.urlopen('http://{a.host}/linux-run.sh').read())\"")
    send(a.uart_cmd, f"{fetch} | sh -s {a.flavour} {a.runs} {a.core} {a.host}\n")
    if not wait_for(a.uart_log, run_off, b"LINUX_CM_DONE", 3 * 3600):
        print("benchmark did not finish", flush=True)
        return 1
    here = os.path.dirname(os.path.abspath(__file__))
    return subprocess.call([sys.executable, os.path.join(here, "parse_linux.py"),
                            "--uart-log", a.uart_log, "--offset", str(run_off), "--csv", a.csv,
                            "--board-config", a.board_config, "--mhz", str(a.mhz)])


if __name__ == "__main__":
    sys.exit(main())
