## 2024-05-14 - Pre-calculating Patterns inside Begin Block
**Learning:** PowerShell pipeline performance is heavily bottlenecked by string interpolation (like `"*$keyword*"`) inside `process` blocks. This gets re-evaluated per object traversing the pipeline.
**Action:** Always pre-calculate patterns in the `begin` block and store them in function-scoped variables to ensure proper encapsulation and avoid redundant per-object allocations when dealing with string interpolation.

## 2024-05-14 - Direct Property Access vs Reflection
**Learning:** Prefer direct property access (e.g., `$InputObject.Name`) over reflection-based lookup (`$InputObject.PSObject.Properties['Name']`) for performance. This treats missing properties and null values identically while being significantly faster.
**Action:** When working with pipeline objects, use direct property access unless strict type checking or reflection is strictly necessary.