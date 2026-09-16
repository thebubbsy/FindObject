# FindObject

**The object-aware `grep` that PowerShell should have shipped with.**

```powershell
Get-Process | fob "chrome OR firefox NOT helper"
```

That's it. That's the whole pitch. You just filtered processes with boolean logic,
natural-language syntax, and zero scriptblock ceremony.

---

## The Problem

PowerShell's pipeline is world-class. But *finding things in it* is stuck in 2006:

```powershell
# The status quo: verbose, noisy, slow
Get-Process | Where-Object { $_.ProcessName -like '*chrome*' -or $_.ProcessName -like '*firefox*' } |
    Where-Object { $_.ProcessName -notlike '*helper*' }
```

Two `Where-Object` calls. Three wildcard patterns. A scriptblock. Curly braces. Dollar signs.
For what is conceptually just: *"give me chrome or firefox, not helper."*

`Select-String` only works on text. `Where-Object` works on objects but makes you write
a lambda for every filter. There is no built-in command that says *"filter these objects
by name, with the logic I'd type in a search bar."*

FindObject is that command.

## The Solution

```powershell
Get-Process | fob "chrome OR firefox NOT helper"
```

One verb. One string. Boolean logic parsed from natural language. Objects flow through
the pipeline untouched. It's `grep` for the object pipeline — the missing primitive
between `Where-Object` and your eyeballs.

## Why It's Fast

FindObject v2 doesn't use PowerShell's `-like` wildcard engine. It calls
`[String]::Contains()`, `[String]::StartsWith()`, and `[String]::IndexOf()` directly —
the same BCL methods that power .NET's own search infrastructure.

| Approach | 100k objects | Mechanism |
|----------|-------------|-----------|
| `Where-Object { $_.Name -like '*x*' }` | ~14s | Wildcard → Regex engine |
| `FindObject "x"` (v2) | ~3s | `String.IndexOf` (SIMD-vectorized) |
| `FindObject "x" -First 10` | <0.5s | Early pipeline termination |

Pre-computed `StringComparison` enums, short-circuit clause evaluation, and `-First N`
early termination mean you stop paying for objects you don't need.

## Installation

```powershell
Install-Module FindObject -Scope CurrentUser
Import-Module FindObject
```

Requires PowerShell 5.1+. Works on Windows, macOS, and Linux. Zero dependencies.

## Usage

### The Basics

```powershell
# Substring match on .Name (default)
Get-ChildItem | fob "report"

# Alias 'fob' keeps your hands on the keyboard
Get-Service | fob "sql"
```

### Boolean Logic

Keywords combine with AND / OR / NOT — as a natural string or array elements:

```powershell
# Natural language
Get-Process | fob "chrome OR firefox NOT helper"

# Array syntax (same result)
Get-Process | fob "chrome", "or", "firefox", "not", "helper"

# AND: must contain both
Get-ChildItem | fob "report AND 2025"

# Bare keywords default to OR
Get-ChildItem | fob ".ps1", ".psm1"
```

### Matching Modes

```powershell
fob "chr"                        # Contains (default) — substring anywhere
fob "chr" -Mode StartsWith       # Prefix only
fob "fndobj" -Mode Fuzzy         # Subsequence: f-n-d-o-b-j in order
fob "chrome.exe" -Mode Exact     # Full string equality
fob 'file\d+\.log' -Mode Regex   # .NET regular expression
```

### Any Property — or All of Them

```powershell
# Target a specific property
Get-Process | fob "svchost" -Property ProcessName

# Search every string property on the object
Get-Service | fob "running" -Property *

# Match plain strings / objects with no Name
"apple pie", "banana bread" | fob "pie" -AsString
```

### Result Control

```powershell
# Stop after N matches (early termination — huge on large pipelines)
Get-ChildItem -Recurse | fob ".ps1" -First 10

# Page through results
Get-Process | fob "svc" -Skip 5 -First 5

# Just the count
Get-ChildItem | fob ".log" -Count

# Boolean check (stops at first match)
if (Get-Process | fob "chrome" -Quiet) { "Chrome is running" }
```

### Visual Highlighting

```powershell
# Colorized preview in console; real objects still flow through the pipeline
Get-Process | fob "chrome" -Highlight | Stop-Process -WhatIf
```

### Persistable Defaults

```powershell
Set-FindObjectConfig -Mode Fuzzy -Highlight -Persist
# Every future session now defaults to fuzzy matching with highlights
Get-FindObjectConfig
```

## Design Principles

1. **Objects in, objects out.** FindObject never transforms, wraps, or formats.
   The pipeline gets the same objects it would have gotten from `Where-Object`.

2. **One verb to learn.** `fob` is three characters. The syntax is a search bar,
   not a scriptblock.

3. **Fast by default, faster on demand.** BCL string methods on the hot path;
   `-First N` when you don't need everything.

4. **Composable.** It's a filter. Chain it, pipe from it, pipe into it.
   `Get-ChildItem -Recurse | fob ".ps1 NOT test" | fob "module" -Property FullName`

5. **Zero dependencies.** One `.psm1` file. No assemblies, no NuGet, no build step.
   Copy it to your module path and go.

## Parameter Reference

| Parameter | Description |
|-----------|-------------|
| `SearchTerms` | Keywords + optional `and`/`or`/`not` operators |
| `InputObject` | Pipeline input (automatic) |
| `Mode` | `Contains` · `StartsWith` · `Fuzzy` · `Exact` · `Regex` |
| `Property` | Target property (default `Name`; `*` = all string props) |
| `AsString` | Match the object's `ToString()` output |
| `CaseSensitive` | Ordinal case-sensitive comparison |
| `Highlight` | ANSI colorized console preview |
| `First` | Emit at most N matches (early termination) |
| `Skip` | Discard the first N matches |
| `Count` | Return match count instead of objects |
| `Quiet` | Return `$true`/`$false` (stops at first match) |

## Real-World One-Liners

```powershell
# Find the service you can't quite remember the name of
Get-Service | fob "windw" -Mode Fuzzy              # → WinDefend, WinRM, ...

# Kill orphaned node processes except your dev server
Get-Process | fob "node NOT inspect" | Stop-Process

# Audit: which GPOs mention "password"?
Get-GPO -All | fob "password" -Property DisplayName -Count

# Quick existence check in CI
$hasTests = Get-ChildItem -Recurse | fob ".Tests.ps1" -Quiet

# Find large files matching a pattern, page by page
Get-ChildItem -Recurse | fob ".log" -First 20 | Sort-Object Length -Descending
```

## Microsoft Graph / Intune Integration (FindObject.Intune)

FindObject includes an optional, decoupled Intune submodule (`FindObject.Intune.psd1`). The core `FindObject` module remains zero-dependency and ultra-lightweight, while `FindObject.Intune` provides direct Microsoft Graph integration without requiring the heavyweight `Microsoft.Graph` SDK or manual REST queries.

To use the Intune cmdlets, import the submodule:
```powershell
Import-Module .\FindObject.Intune.psd1
```

### Connect

```powershell
# Interactive (device code flow — no app registration needed)
Connect-FindObjectGraph -TenantId "contoso.onmicrosoft.com"

# Automation / CI (app registration with client secret)
Connect-FindObjectGraph -TenantId $tenantId -ClientId $appId -ClientSecret $secret
```

### Search Your Fleet

```powershell
# Find a device by name
Get-IntuneDevice | fob "TONY-PC"

# Non-compliant Windows devices
Get-IntuneDevice | fob "windows" -Property operatingSystem |
    Where-Object complianceState -ne 'compliant'

# Or do it all in fob:
Get-IntuneDevice | fob "windows NOT compliant" -Property operatingSystem,complianceState

# Apps: what's deployed that mentions chrome or edge?
Get-IntuneApp | fob "chrome OR edge NOT update"

# Compliance policies mentioning encryption
Get-IntuneCompliancePolicy | fob "bitlocker OR encryption"

# Config profiles: find your WiFi and VPN profiles
Get-IntuneConfigProfile | fob "wifi OR vpn"

# Autopilot: which Dell devices haven't enrolled yet?
Get-IntuneAutopilotDevice | fob "dell" -Property manufacturer |
    Where-Object enrollmentState -ne 'enrolled'

# Enrollment restrictions
Get-IntuneEnrollment | fob "limit OR restrict"

# Server-side filter + client-side fob (best of both worlds)
Get-IntuneDevice -Filter "operatingSystem eq 'iOS'" | fob "ipad" -First 5
```

### Available Intune Cmdlets

| Command | Graph Endpoint |
|---------|---------------|
| `Get-IntuneDevice` | `/deviceManagement/managedDevices` |
| `Get-IntuneApp` | `/deviceAppManagement/mobileApps` |
| `Get-IntuneCompliancePolicy` | `/deviceManagement/deviceCompliancePolicies` |
| `Get-IntuneConfigProfile` | `/deviceManagement/deviceConfigurations` |
| `Get-IntuneAutopilotDevice` | `/deviceManagement/windowsAutopilotDeviceIdentities` |
| `Get-IntuneEnrollment` | `/deviceManagement/deviceEnrollmentConfigurations` |

All cmdlets handle pagination automatically, accept `-Filter` (OData, server-side),
`-Select` (property projection), and `-Top` (page size).

## Requirements

- PowerShell 5.1+ (Desktop or Core)
- Windows, macOS, or Linux
- No external dependencies

## License

[MIT](LICENSE)

## Author

**Matthew Bubb** — [github.com/thebubbsy](https://github.com/thebubbsy)
