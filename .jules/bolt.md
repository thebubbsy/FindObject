## 2024-05-28 - Hidden Performance Penalties in PowerShell Write-Verbose
**Learning:** In high-throughput PowerShell pipeline functions, arguments to debugging commands like `Write-Verbose` are evaluated before the command is executed, even if the verbose stream is turned off. Complex string interpolations, especially those using reflection (e.g., `$($InputObject.GetType().FullName)`), introduce massive hidden performance penalties per object.
**Action:** Remove expensive reflection or string interpolations from `Write-Verbose` or `Write-Debug` statements inside the `process` block. Pre-calculate values or use simple property access instead.

## 2024-05-28 - Repository Bloat from Downloaded Dependencies
**Learning:** Downloading environment dependencies like `.deb` files for PowerShell installation into the workspace can inadvertently get committed and cause severe repository bloat if not immediately cleaned up.
**Action:** Always ensure any binaries or packages downloaded for environment setup are explicitly removed via `rm` before initiating git commands or PR creation.
