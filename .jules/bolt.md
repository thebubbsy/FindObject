## 2024-03-22 - Pre-calculated patterns optimization
**Learning:** PowerShell pipeline performance is heavily bottlenecked by string interpolation (`"*$keyword*"`) inside `process` blocks. This triggers string allocation for every input object times the number of keywords.
**Action:** Pre-calculate the wildcard patterns in the `begin` block and store them in function-scoped variables to ensure proper encapsulation and avoid redundant per-object allocations.

## 2024-03-22 - Fast path returns and variable scoping
**Learning:** Returning early in a process block inside the pipeline is much faster than setting flags. Variables scoped in the `begin` block automatically persist to the `process` block.
**Action:** Use early returns (`return`) instead of tracking a `$match` variable, and use `begin` block initialization rather than the discouraged `$script:` scope.

## 2024-03-22 - Array indexing vs Object Casting
**Learning:** In PowerShell, `-isnot [string]` followed by type casting (e.g., `[string]$objectName`) is faster and avoids potential null reference exceptions compared to calling `.ToString()` on arbitrary pipeline objects. Direct property access (e.g. `$InputObject.Name`) is preferred.
**Action:** Avoid `.ToString()`, use type casts `[string]$object` instead for fast and safe string conversion.

## 2024-03-22 - High-throughput iteration in PowerShell
**Learning:** Iterating over arrays using a standard `for` loop with a pre-cached `.Length` property is measurably faster than using `foreach` inside high-throughput `process` blocks.
**Action:** Use `for` loops caching the array length for filtering loops in `process` blocks.
