## Dispatches a selected optional toolchain application entry module.
{.warning[UnusedImport]: off.}

import lib/mem
import lib/string
import lib/types


discard sizeof(CSize)


when defined(toolchainApp_rkxwritecheck):
  import apps/rkxwritecheck/rkxwritecheck
elif defined(toolchainApp_rkas):
  import apps/rkas/rkas
elif defined(toolchainApp_rkcc):
  import apps/rkcc/rkcc
else:
  {.error: "missing toolchain app define".}
