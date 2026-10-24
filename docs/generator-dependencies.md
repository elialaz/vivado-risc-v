# Generator dependencies

CPU generators are pinned Git submodules below `generators/`.  The gitlink in
this repository is the reproducible source of truth; the `branch` entries in
`.gitmodules` only document the upstream update channel.

| Generator | Upstream channel | Pinned revision |
| --- | --- | --- |
| BOOM | `riscv-boom/riscv-boom`, `master` (stable pin, matches rocket-chip) | `b4283f3c07e1833d50d695dc3fc2b2734726b598` |
| CVA6 | `openhwgroup/cva6`, `master` | `81245a47fad8fe1a5d562d953ef2662e099def76` |
| GRLIB GPL | Frontgrade Gaisler 2026.2-b4300 | `2d4ae1f15bd942172e6aa0f9282bfeed73293f68` |

Frontgrade Gaisler publishes GRLIB GPL as release archives rather than through
an official Git remote.  `generators/grlib` therefore uses the TUT-ASI Git
mirror of the unmodified release.  Its pinned tag is
`grlib-gpl-2026.2-b4300`; the canonical archive is:

<https://download.gaisler.com/products/GRLIB/bin/grlib-gpl-2026.2-b4300.tar.gz>

Do not modify generator submodules in place. Repository-specific CVA6 and
GRLIB integration belongs in this repository's HDL wrappers, board shell, and
build scripts. BOOM remains part of the Scala/Rocket-Chip generator path.

Tool requirements beyond `make apt-install`: `python3` and `patch` (CVA6 and
NOEL-V boot ROM generation, CVA6 patch copies), the repository RISC-V
toolchain in `workspace/gcc`, and Vivado with a Kintex-7 license for
Genesys 2. GRLIB's `make scripts` generates the NOEL-V source manifest in a
scratch copy, so the submodule stays read-only. GRMON (Frontgrade Gaisler,
evaluation version is enough) is needed only for NOEL-V JTAG debug, and GHDL
only for the optional NOEL-V simulation scripts.

Clone all generator dependencies, including CVA6's own pinned dependencies,
with:

```sh
git submodule update --init --recursive
```

The SoC backend is selected exclusively through `CONFIG`; `BOARD` continues
to select the common board shell and peripheral set. The configurations are:

| CONFIG | Core |
| --- | --- |
| `rocket64w1v4` / `rocket64x1v4` / `rocket64y1v4` / `rocket64z1v4` | BOOM v4 Small / Medium / Large / Mega |
| `rocket64cva6` | CVA6 |
| `rocket64noelv` | NOEL-V from GRLIB |

The CVA6 and NOEL-V names select native, non-Scala SoCs. They do not insert an
external core into Rocket Chip. The detailed contract and current migration
state are in `docs/native-axi-refactor.md`.

The intended Genesys 2 commands remain:

```sh
make CONFIG=rocket64cva6 BOARD=genesys2 vivado-project
make CONFIG=rocket64noelv BOARD=genesys2 vivado-project
```

The NOEL-V source loader consumes GRLIB's official ordered manifest. Generated
GRLIB scripts are build artifacts; the pinned, unmodified submodule plus the
repository-owned native wrapper are the reproducible inputs. The native
wrapper uses `noelvsys` and GRLIB's official AHB-to-AXI bridge, without a
TileLink path.
