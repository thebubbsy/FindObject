
## 2024-03-10 - Pre-calculate Wildcard Patterns in PowerShell Begin Block
**Learning:** PowerShell pipeline processing is heavily bottlenecked by string interpolation within loops. Using `"*$keyword*"` inside a `process` block means allocating memory for a new string for every single object on the pipeline, which leads to massive overheads when processing tens of thousands of objects.
**Action:** When filtering pipeline inputs against dynamically generated wildcard patterns, always pre-calculate those patterns once in the `begin` block and store them in a function-scoped variable to iterate over in the `process` block. This simple change yields a roughly 2.5x performance improvement.
