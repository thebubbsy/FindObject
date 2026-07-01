# FindObject PowerShell Module

Filter pipeline objects by keyword, with AND/OR/NOT logic, Contains/StartsWith/Fuzzy matching, and optional
colorized highlighting.

## Features

- **Logical Filtering**: Combine keywords with AND, OR, and NOT
- **Natural or array syntax**: `"chrome OR firefox NOT helper"` or `"chrome", "or", "firefox"`
- **Matching modes**: Contains (default), StartsWith, or Fuzzy (subsequence) matching
- **Any property, or none**: Matches `.Name` by default, `-Property` for anything else, `-AsString` for plain strings/objects with no name
- **Visually pleasing output**: `-Highlight` prints a colorized preview while still passing the real objects through the pipeline
- **Configurable defaults**: `Get-FindObjectConfig` / `Set-FindObjectConfig` (optionally persisted across sessions)
- **Alias Support**: Use `fob` as a shorthand for `Find-ObjectByName`

## Installation

```powershell
# Install from PowerShell Gallery
Install-Module -Name FindObject -Scope CurrentUser

# Import the module
Import-Module FindObject
```

## Usage

### Basic Filtering

```powershell
# Find objects whose Name contains "test"
Get-ChildItem | Find-ObjectByName "test"

# Using the alias
Get-ChildItem | fob "test"
```

### Logical Operators

Keywords can be combined either as separate array elements or as one natural-language string. A keyword with no
operator in front of it defaults to OR against everything matched so far.

```powershell
# AND - name must contain both terms
Get-ChildItem | fob "test", "and", "file"
Get-ChildItem | fob "test AND file"

# OR - name must contain at least one term (also the default with no operator)
Get-ChildItem | fob "test", "file"
Get-ChildItem | fob "test OR file"

# NOT - exclude items containing a term
Get-ChildItem | fob "test NOT backup"

# Mixed
Get-Process | fob "chrome OR firefox NOT helper"
```

### Matching Modes

```powershell
# Contains (default): wildcard substring match
Get-Process | fob "chrome"

# StartsWith
Get-Process | fob "chr" -Mode StartsWith

# Fuzzy: characters must appear in order, not necessarily together
Get-Process | fob "crome" -Mode Fuzzy   # still matches "chrome.exe"
```

### Any Property, or the Object Itself

```powershell
# Match a property other than Name
Get-Process | fob "svchost" -Property ProcessName

# Match plain strings, or objects with no useful Name property
"apple pie", "banana bread" | fob "pie" -AsString
```

### Visual Highlighting

```powershell
# Prints a colorized preview to the console, and still emits the real objects down the pipeline
Get-Process | fob "chrome" -Highlight | Stop-Process -WhatIf
```

### Configuration

```powershell
# See current defaults
Get-FindObjectConfig

# Change defaults for this session
Set-FindObjectConfig -Mode Fuzzy -Highlight

# Change defaults and remember them for future sessions
Set-FindObjectConfig -Mode StartsWith -CaseSensitive:$false -Persist
```

## Real-World Examples

```powershell
# Find all PowerShell scripts except backup files
Get-ChildItem -Recurse | fob ".ps1 NOT backup"

# Find files with either "log" or "txt" in the name
Get-ChildItem | fob "log OR txt"

# Find files containing both "report" and "2024"
Get-ChildItem | fob "report", "and", "2024"

# Fuzzy-find a process when you're not sure of the exact name
Get-Process | fob "pwsh" -Mode Fuzzy
```

## Parameters

- **SearchTerms** (alias `FilterString`): Keywords, optionally combined with `and`/`or`/`not`
- **InputObject**: Objects to filter (accepts pipeline input)
- **Mode**: `Contains` (default), `StartsWith`, or `Fuzzy`
- **Property**: Property to match against (default `Name`)
- **AsString**: Match against the object's own string form instead of a named property
- **CaseSensitive**: Case-sensitive comparison (default off)
- **Highlight**: Print a colorized preview to the console in addition to passing objects through

## Requirements

- PowerShell 5.1 or later
- Works on Windows, macOS, and Linux

## License

MIT License - See [LICENSE](LICENSE) file for details

## Author

Matthew Bubb

## Repository

https://github.com/thebubbsy/FindObject
