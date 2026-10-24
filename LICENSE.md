# MIT License

Copyright (c) 2021-2025 Eugene Tarassov

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

---

## Submodule License Summary

This repository integrates multiple third-party components under their respective open source licenses:

| Component         | License(s)              | Notes |
|------------------|--------------------------|-------|
| linux-stable     | [GPL-2.0](https://www.kernel.org/doc/html/v4.18/process/license-rules.html) | Not relicensed; included as external reference |
| u-boot           | [GPL-2.0+](https://github.com/u-boot/u-boot/tree/master/Licenses) | Not relicensed; included as external reference |
| rocket-chip      | [Apache 2.0](https://github.com/chipsalliance/rocket-chip/blob/master/LICENSE.SiFive), [UCB](https://github.com/chipsalliance/rocket-chip/blob/master/LICENSE.Berkeley), [UCB chisel-jtag](https://github.com/chipsalliance/rocket-chip/blob/master/LICENSE.jtag) | Multi-licensed: Apache 2.0 from SiFive, BSD-style for Rocket and chisel-jtag |
| verilog-ethernet | [MIT](https://github.com/alexforencich/verilog-ethernet/blob/master/COPYING) | Standard MIT license |
| sifive-cache     | [Apache 2.0](https://github.com/chipsalliance/rocket-chip-inclusive-cache/blob/main/LICENSE) | From SiFive |
| testchipip       | [BSD 3-Clause](https://github.com/ucb-bar/testchipip/blob/master/LICENSE) | Permissive BSD-style |
| riscvboom        | [BSD 3-Clause](https://github.com/riscv-boom/riscv-boom/blob/master/LICENSE), [Apache 2.0 (SiFive)](https://github.com/riscv-boom/riscv-boom/blob/master/LICENSE.SiFive) | Dual-licensed |
| CVA6             | [Solderpad Hardware License 0.51](https://github.com/openhwgroup/cva6/blob/master/LICENSE) (some files SHL-2.0/2.1 or Apache 2.0) | Official OpenHW Group source, not relicensed; small local patches in `patches/cva6/` |
| GRLIB GPL        | [GPL-2.0-only](https://www.gaisler.com/grlib-ip-library) | Frontgrade Gaisler release (includes NOEL-V) carried through a Git mirror; not relicensed or modified |
| gemmini          | [BSD-style (Berkeley)](https://github.com/ucb-bar/gemmini/blob/master/LICENSE) | Custom BSD variant from UC Berkeley |
| opensbi          | [BSD 2-Clause](https://github.com/riscv-software-src/opensbi/blob/master/COPYING.BSD) | Permissive |
| coremark         | [Apache 2.0 and AUA](https://github.com/eembc/coremark/blob/main/LICENSE.md) | Apache for code, trademark use restricted by AUA |
| benchmark-dhrystone | [via SiFive, no license](https://github.com/sifive/benchmark-dhrystone/blob/master/LICENSE?tab=License-1-ov-file) | Code is many decades old and re-shared by SiFive, No explicit license  |

Note on CoreMark: The software is under Apache 2.0, but the "CoreMark" trademark and name usage is restricted by the Acceptable Use Agreement (AUA). Do not use the name in modified benchmarks or without compliance.

---

## License Compatibility Notes

The original code in this repository is licensed under MIT. Third-party
submodules and generated or synthesized designs remain subject to their own
licenses; no submodule is relicensed by this repository. In particular, the
NOEL-V configuration incorporates GRLIB GPL HDL into the FPGA design and is
subject to the applicable GPL-2.0 requirements when it is copied or
distributed. This summary is informational and is not legal advice; consult
the complete license files in each dependency before distributing sources,
generated HDL, or FPGA artifacts.
