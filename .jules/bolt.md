## 2024-05-24 - PowerShell Pipeline String Interpolation
**Learning:** Performing string interpolation (like `"*$keyword*"`) inside the `process` block of a PowerShell Advanced Function processing pipeline input is relatively expensive and results in repeated work/allocations for every object in the pipeline.
**Action:** Pre-calculate any static patterns or concatenated strings based on arguments in the `begin` block. Store these pre-calculated values in variables and use those directly in the `process` block to avoid redundant per-object allocations and overhead.
