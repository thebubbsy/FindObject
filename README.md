# FindObject PowerShell Module

Filter objects by name with logical operators (AND/OR/NOT) for powerful object filtering in PowerShell.

## Features

- **Logical Filtering**: Use AND, OR, and NOT operators to filter objects by name
- **Flexible Syntax**: Multiple ways to express filter conditions
- **Pipeline Support**: Works seamlessly with PowerShell pipeline
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
# Find objects containing "test"
Get-ChildItem | Find-ObjectByName "test"

# Using the alias
Get-ChildItem | fob "test"
```

### Logical Operators

```powershell
# AND operator - name must contain both terms
Get-ChildItem | fob "test", "file"
Get-ChildItem | fob "test AND file"

# OR operator - name must contain at least one term
Get-ChildItem | fob "test OR file"

# NOT operator - exclude items containing term
Get-ChildItem | fob "test NOT backup"
```

### Real-World Examples

```powershell
# Find all PowerShell scripts except backup files
Get-ChildItem -Recurse | fob ".ps1 NOT backup"

# Find files with either "log" or "txt" in the name
Get-ChildItem | fob "log OR txt"

# Find files containing both "report" and "2024"
Get-ChildItem | fob "report", "2024"

# Complex filtering with multiple operators
Get-Process | fob "chrome OR firefox NOT helper"
```

## Examples

### File System

```powershell
# Find all JavaScript or TypeScript files
Get-ChildItem -Recurse | fob ".js OR .ts"

# Find markdown files that aren't README files
Get-ChildItem | fob ".md NOT readme"

# Find all test files
Get-ChildItem -Recurse | fob "test", ".spec"
```

### Processes

```powershell
# Find Chrome processes but not helper processes
Get-Process | fob "chrome NOT helper"

# Find either Firefox or Edge processes
Get-Process | fob "firefox OR msedge"
```

### Services

```powershell
# Find Windows Update services
Get-Service | fob "windows", "update"

# Find SQL or MySQL services
Get-Service | fob "sql OR mysql"
```

## Syntax

### AND Logic (All terms must match)
```powershell
fob "term1", "term2"          # Array syntax
fob "term1 AND term2"          # Explicit AND
fob "term1", "term2", "term3"  # Multiple terms
```

### OR Logic (At least one term must match)
```powershell
fob "term1 OR term2"
fob "term1 OR term2 OR term3"
```

### NOT Logic (Exclude matches)
```powershell
fob "term1 NOT term2"
fob "include OR this NOT exclude"
```

## Parameters

- **FilterString**: The filter expression (supports arrays for AND logic)
- **InputObject**: Objects to filter (accepts pipeline input)

## Requirements

- PowerShell 5.1 or later
- Works on Windows, macOS, and Linux

## License

MIT License - See [LICENSE](LICENSE) file for details

## Author

Matthew Bubb

## Repository

https://github.com/thebubbsy/FindObject
