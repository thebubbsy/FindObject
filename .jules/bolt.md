## 2024-05-26 - String interpolation in Write-Verbose inside high-throughput process block
**Learning:** In PowerShell, arguments to commands like `Write-Verbose` are evaluated *before* the command executes, even if verbose logging is disabled. This means expensive operations like `$($InputObject.GetType().FullName)` inside the string will execute for every pipeline object, creating a massive hidden performance penalty.
**Action:** Avoid complex string interpolation or reflection inside `Write-Verbose` or `Write-Debug` statements within a `process` block unless absolutely necessary.
