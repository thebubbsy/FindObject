## 2025-01-01 - Avoid reflection in high-throughput `process` blocks
**Learning:** PowerShell evaluates string interpolation (especially with reflection like `$($InputObject.GetType().FullName)`) in `Write-Verbose` *before* checking if verbose logging is actually enabled. In a high-throughput pipeline `process` block, this causes a massive hidden performance penalty even when the user hasn't requested `-Verbose`.
**Action:** Remove expensive reflection from `Write-Verbose` and `Write-Debug` statements in `process` blocks.

## 2025-01-01 - Pre-calculate string interpolation patterns
**Learning:** PowerShell pipeline performance is bottlenecked by repeated string interpolation inside `process` loops (e.g., `"*$keyword*"`).
**Action:** Optimize by pre-calculating patterns in the `begin` block and storing them in function-scoped variables.

## 2025-01-01 - Optimize loop iteration
**Learning:** Iterating over arrays using a standard `for` loop with a pre-cached `.Length` property is measurably faster than using `foreach` inside high-throughput `process` blocks.
**Action:** Replace `foreach` loops with `for` loops and cached length for inner loop iterations.
