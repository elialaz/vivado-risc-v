#!/bin/sh
# Board side of the Linux CoreMark runs (served by the host, run as root):
#   python3 -c "<fetch linux-run.sh>" | sh -s <flavour> <runs> <core> [host]
# (the board's Debian image has python3 but no wget/curl)
# flavour: zb (CVA6/NOEL-V), gc (BOOM) or b (Shuttle). Prints one LINUX_CM line per run.
FLAV=$1; RUNS=$2; CORE=$3; HOST=${4:-192.168.6.72:8000}
cd /tmp || exit 1
fetch() {
  python3 -c "import sys,urllib.request as u; open(sys.argv[2],'wb').write(u.urlopen(sys.argv[1]).read())" "$1" "$2"
}
for m in base opt opt2; do
  fetch http://$HOST/linux-$FLAV-$m cm-$m && chmod +x cm-$m || { echo "LINUX_CM_ERROR fetch $m"; continue; }
  i=1
  while [ $i -le $RUNS ]; do
    ./cm-$m > cm.out 2>&1
    ips=$(sed -n 's/^Iterations\/Sec *: *//p' cm.out)
    ok=$(grep -c 'Correct operation validated' cm.out)
    echo "LINUX_CM core=$CORE mode=$m run=$i ips=$ips validated=$ok"
    i=$((i + 1))
  done
done
echo LINUX_CM_DONE
