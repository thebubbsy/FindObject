## 2026-03-31 - PowerShell Pipeline Bottlenecks
**Learning:** String interpolation ("*$keyword*") and reflection ($Object.GetType().FullName) inside `process` blocks cause massive performance penalties, even if `Write-Verbose` is off, because arguments are evaluated before execution. `foreach` is also measurably slower than a `for` loop with a cached `.Length`.
**Action:** Pre-calculate wildcard patterns in the `begin` block. Replace `foreach` with `for($i=0; $i -lt $len; $i++)`. Avoid reflection in high-throughput `process` blocks.
