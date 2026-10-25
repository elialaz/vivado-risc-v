// NaxRiscv core configuration for naxriscv.platform.litex.NaxGen
// (--scala-file). NaxGen provides memoryRegions, xlen, resetVector, debug,
// arg() and the plugins buffer; the regions come from the --memory-region
// arguments in mk/native.mk.

import spinal.core._
import spinal.lib._
import naxriscv._
import naxriscv.utilities._

def ioRange(address: UInt): Bool = memoryRegions.filter(_.isIo).map(_.mapping.hit(address)).orR
def fetchRange(address: UInt): Bool = memoryRegions.filter(_.isExecutable).map(_.mapping.hit(address)).orR

plugins ++= Config.plugins(
  xlen          = xlen,
  ioRange       = ioRange,
  fetchRange    = fetchRange,
  resetVector   = resetVector,
  aluCount      = arg("alu-count", 2),
  decodeCount   = arg("decode-count", 2),
  debugTriggers = 0,
  withRvc       = arg("rvc", true),
  withLoadStore = true,
  withMmu       = true,
  withFloat     = arg("rvf", true),
  withDouble    = arg("rvd", true),
  withDebug     = debug,
  withEmbeddedJtagTap = false,
  withEmbeddedJtagInstruction = false,
  withCoherency = true,
  withRdTime    = true
)
