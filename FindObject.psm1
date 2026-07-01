#region Configuration

$script:FindObjectConfigPath = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'FindObject\config.json'

$script:FindObjectConfig = @{
    Mode          = 'Contains'   # Contains | StartsWith | Fuzzy
    Property      = 'Name'
    CaseSensitive = $false
    Highlight     = $false
}

if (Test-Path -LiteralPath $script:FindObjectConfigPath) {
    try {
        $saved = Get-Content -LiteralPath $script:FindObjectConfigPath -Raw | ConvertFrom-Json
        foreach ($key in @('Mode', 'Property', 'CaseSensitive', 'Highlight')) {
            if ($null -ne $saved.$key) { $script:FindObjectConfig[$key] = $saved.$key }
        }
    } catch {
        Write-Verbose "Failed to load persisted FindObject config from '$script:FindObjectConfigPath': $_"
    }
}

function Get-FindObjectConfig {
    <#
    .SYNOPSIS
    Returns the current default settings used by Find-ObjectByName when a parameter isn't explicitly supplied.

    .EXAMPLE
    Get-FindObjectConfig
    #>
    [CmdletBinding()]
    param()
    [PSCustomObject]$script:FindObjectConfig
}

function Set-FindObjectConfig {
    <#
    .SYNOPSIS
    Changes the default Mode, Property, CaseSensitive, or Highlight settings used by Find-ObjectByName.

    .PARAMETER Persist
    Also saves the settings to disk so they apply in future PowerShell sessions.

    .EXAMPLE
    Set-FindObjectConfig -Mode Fuzzy -Highlight -Persist
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Contains', 'StartsWith', 'Fuzzy')]
        [string]$Mode,

        [string]$Property,

        [switch]$CaseSensitive,

        [switch]$Highlight,

        [switch]$Persist
    )

    if ($PSBoundParameters.ContainsKey('Mode')) { $script:FindObjectConfig.Mode = $Mode }
    if ($PSBoundParameters.ContainsKey('Property')) { $script:FindObjectConfig.Property = $Property }
    if ($PSBoundParameters.ContainsKey('CaseSensitive')) { $script:FindObjectConfig.CaseSensitive = $CaseSensitive.IsPresent }
    if ($PSBoundParameters.ContainsKey('Highlight')) { $script:FindObjectConfig.Highlight = $Highlight.IsPresent }

    if ($Persist) {
        $configDir = Split-Path -Parent $script:FindObjectConfigPath
        if (-not (Test-Path -LiteralPath $configDir)) {
            New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        }
        $script:FindObjectConfig | ConvertTo-Json | Set-Content -LiteralPath $script:FindObjectConfigPath -Encoding utf8
    }

    [PSCustomObject]$script:FindObjectConfig
}

#endregion

#region Internal helpers

function Test-FindObjectFuzzyMatch {
    # Subsequence match: every character of $Pattern must appear in $Text, in order, not necessarily contiguous.
    param(
        [string]$Text,
        [string]$Pattern,
        [bool]$CaseSensitive
    )

    if ([string]::IsNullOrEmpty($Pattern)) { return $true }
    if ([string]::IsNullOrEmpty($Text)) { return $false }

    $t = if ($CaseSensitive) { $Text } else { $Text.ToLowerInvariant() }
    $p = if ($CaseSensitive) { $Pattern } else { $Pattern.ToLowerInvariant() }

    $cursor = 0
    foreach ($ch in $p.ToCharArray()) {
        $idx = $t.IndexOf($ch, $cursor)
        if ($idx -lt 0) { return $false }
        $cursor = $idx + 1
    }
    return $true
}

function ConvertTo-FindObjectClauses {
    # Parses -SearchTerms into an ordered list of {Operator, Keyword} clauses.
    # Supports both array syntax (`"a","and","b"`) and natural single-string syntax (`"a AND b"`, `"chrome OR firefox NOT helper"`).
    # A keyword with no preceding operator defaults to OR against the accumulated result, matching the module's original behavior.
    param([string[]]$SearchTerms)

    $tokens = [System.Collections.Generic.List[string]]::new()
    foreach ($term in $SearchTerms) {
        if ([string]::IsNullOrWhiteSpace($term)) { continue }

        if ($term -match '(?i)(^|\s)(and|or|not)(\s|$)') {
            foreach ($piece in ($term -split '\s+')) {
                if (-not [string]::IsNullOrWhiteSpace($piece)) { $tokens.Add($piece) }
            }
        } else {
            $tokens.Add($term)
        }
    }

    $clauses = [System.Collections.Generic.List[hashtable]]::new()
    $pendingOperator = $null

    foreach ($token in $tokens) {
        if ($token -ieq 'and') { $pendingOperator = 'AND'; continue }
        if ($token -ieq 'or') { $pendingOperator = 'OR'; continue }
        if ($token -ieq 'not') { $pendingOperator = 'NOT'; continue }

        $operator = if ($clauses.Count -eq 0) { $null } elseif ($pendingOperator) { $pendingOperator } else { 'OR' }
        $clauses.Add(@{ Operator = $operator; Keyword = $token })
        $pendingOperator = $null
    }

    if ($clauses.Count -eq 0) {
        throw "No valid search keywords provided in '-SearchTerms' after parsing operators. Please provide at least one keyword."
    }

    # The comma operator prevents PowerShell from unrolling a single-item List<T> into a bare hashtable
    # on the way out of the pipeline - without it, $clauses.Count downstream would silently report the
    # hashtable's key count (2) instead of the actual clause count (1) whenever there's only one keyword.
    return , $clauses
}

function Format-FindObjectHighlight {
    # Wraps every occurrence of the positive (non-NOT) keywords in ANSI bold-yellow for terminal display.
    param(
        [string]$Text,
        [string[]]$Keywords,
        [bool]$CaseSensitive
    )

    $comparison = if ($CaseSensitive) { [System.StringComparison]::Ordinal } else { [System.StringComparison]::OrdinalIgnoreCase }
    $ranges = [System.Collections.Generic.List[object]]::new()

    foreach ($keyword in $Keywords) {
        if ([string]::IsNullOrEmpty($keyword)) { continue }
        $searchFrom = 0
        while ($searchFrom -le $Text.Length) {
            $idx = $Text.IndexOf($keyword, $searchFrom, $comparison)
            if ($idx -lt 0) { break }
            $ranges.Add(@{ Start = $idx; End = $idx + $keyword.Length })
            $searchFrom = $idx + $keyword.Length
        }
    }

    if ($ranges.Count -eq 0) { return $Text }

    $sorted = $ranges | Sort-Object { $_.Start }
    $boldYellow = "$([char]27)[1;33m"
    $reset = "$([char]27)[0m"
    $sb = [System.Text.StringBuilder]::new()
    $cursor = 0

    foreach ($range in $sorted) {
        if ($range.Start -lt $cursor) { continue }
        [void]$sb.Append($Text.Substring($cursor, $range.Start - $cursor))
        [void]$sb.Append($boldYellow).Append($Text.Substring($range.Start, $range.End - $range.Start)).Append($reset)
        $cursor = $range.End
    }
    [void]$sb.Append($Text.Substring($cursor))

    return $sb.ToString()
}

#endregion

function Find-ObjectByName {
    <#
    .SYNOPSIS
    Filters pipeline objects by matching a property (or the object's own string form) against one or more keywords,
    combined with AND / OR / NOT logic.

    .DESCRIPTION
    Accepts objects via the pipeline and keeps only the ones whose target value matches the given -SearchTerms.
    Keywords can be supplied as separate array elements ("test","and","file") or as a single natural-language
    string ("test AND file", "chrome OR firefox NOT helper"). A keyword with no operator in front of it defaults
    to OR against everything matched so far.

    Matching itself is controlled by -Mode: Contains (default, wildcard substring), StartsWith, or Fuzzy
    (characters of the keyword must appear in order, not necessarily together - e.g. "fndobj" matches "FindObject").

    By default the object's 'Name' property is compared; use -Property to target a different property, or
    -AsString to match against the object's own ToString() representation (useful for plain strings or objects
    with no natural name).

    .PARAMETER SearchTerms
    Keywords to search for, optionally combined with 'and', 'or', or 'not'. Also accepts a single string such as
    "chrome OR firefox NOT helper".

    .PARAMETER InputObject
    The object(s) passed from the pipeline.

    .PARAMETER Mode
    How each keyword is compared against the value: Contains (default), StartsWith, or Fuzzy. Defaults to the
    value from Get-FindObjectConfig.

    .PARAMETER Property
    The property to match against. Defaults to 'Name' (or whatever Set-FindObjectConfig -Property has set).

    .PARAMETER AsString
    Match against the object's own string representation instead of a named property.

    .PARAMETER CaseSensitive
    Perform a case-sensitive comparison. Off by default.

    .PARAMETER Highlight
    Print a colorized preview of each match to the host (in addition to passing the object through the pipeline
    unchanged), with matched text highlighted.

    .EXAMPLE
    Get-Command -Module MicrosoftTeams | Find-ObjectByName "get", "or", "policy"

    .EXAMPLE
    Get-Process | Find-ObjectByName "chrome OR firefox NOT helper"

    .EXAMPLE
    Get-Process | Find-ObjectByName "crome" -Mode Fuzzy
    # Matches "chrome.exe" even though "crome" isn't a literal substring.

    .EXAMPLE
    "apple pie", "banana bread" | Find-ObjectByName "pie" -AsString
    # Matches against the strings themselves rather than a .Name property.

    .NOTES
    - Objects without the target property (or with an empty/whitespace value) are skipped.
    - Comparison is case-insensitive unless -CaseSensitive is specified.
    #>
    [CmdletBinding()]
    [Alias('fob')]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [Alias('FilterString')]
        [string[]]$SearchTerms,

        [Parameter(ValueFromPipeline = $true)]
        [psobject]$InputObject,

        [ValidateSet('Contains', 'StartsWith', 'Fuzzy')]
        [string]$Mode,

        [string]$Property,

        [switch]$AsString,

        [switch]$CaseSensitive,

        [switch]$Highlight
    )

    begin {
        if (-not $PSBoundParameters.ContainsKey('Mode')) { $Mode = $script:FindObjectConfig.Mode }
        if (-not $PSBoundParameters.ContainsKey('Property')) { $Property = $script:FindObjectConfig.Property }
        if (-not $PSBoundParameters.ContainsKey('CaseSensitive')) { $CaseSensitive = [bool]$script:FindObjectConfig.CaseSensitive }
        if (-not $PSBoundParameters.ContainsKey('Highlight')) { $Highlight = [bool]$script:FindObjectConfig.Highlight }

        $clauses = ConvertTo-FindObjectClauses -SearchTerms $SearchTerms

        # Pre-calculate wildcard patterns once so the process block (called once per pipeline object) never
        # rebuilds strings on the hot path - the one genuinely useful idea shared by every "Bolt" perf PR.
        foreach ($clause in $clauses) {
            $clause.Pattern = if ($Mode -eq 'StartsWith') { "$($clause.Keyword)*" } else { "*$($clause.Keyword)*" }
        }
        $clauseCount = $clauses.Count
        $positiveKeywords = @($clauses | Where-Object { $_.Operator -ne 'NOT' } | ForEach-Object { $_.Keyword })
        $isFuzzy = $Mode -eq 'Fuzzy'
        $useCaseSensitiveLike = [bool]$CaseSensitive

        Write-Verbose "Find-ObjectByName initialized. Mode: $Mode, Property: $Property, Clauses: $($clauses.Count)"
    }

    process {
        if ($null -eq $InputObject) { return }

        if ($AsString) {
            $value = [string]$InputObject
        } else {
            $propertyValue = $InputObject.$Property
            if ($null -eq $propertyValue) {
                if ($VerbosePreference -ne 'SilentlyContinue') {
                    Write-Verbose "Input object type '$($InputObject.GetType().FullName)' does not have a '$Property' property or it is null. Skipping."
                }
                return
            }
            $value = if ($propertyValue -is [string]) { $propertyValue } else { [string]$propertyValue }
        }

        if ([string]::IsNullOrWhiteSpace($value)) { return }

        # Inlined rather than routed through a helper function: calling a function per clause per pipeline
        # object is the single biggest cost in a tight PowerShell loop - the thing every "Bolt" PR was
        # (mostly ineffectually) trying to work around. Fuzzy mode still calls out since it's opt-in and
        # not the hot path.
        $firstClause = $clauses[0]
        $result = if ($isFuzzy) {
            Test-FindObjectFuzzyMatch -Text $value -Pattern $firstClause.Keyword -CaseSensitive $useCaseSensitiveLike
        } elseif ($useCaseSensitiveLike) {
            $value -clike $firstClause.Pattern
        } else {
            $value -like $firstClause.Pattern
        }

        for ($i = 1; $i -lt $clauseCount; $i++) {
            $clause = $clauses[$i]
            $operator = $clause.Operator
            if ($operator -eq 'AND' -and -not $result) { continue }
            if ($operator -eq 'OR' -and $result) { continue }

            $clauseMatch = if ($isFuzzy) {
                Test-FindObjectFuzzyMatch -Text $value -Pattern $clause.Keyword -CaseSensitive $useCaseSensitiveLike
            } elseif ($useCaseSensitiveLike) {
                $value -clike $clause.Pattern
            } else {
                $value -like $clause.Pattern
            }

            switch ($operator) {
                'AND' { $result = $result -and $clauseMatch }
                'OR' { $result = $result -or $clauseMatch }
                'NOT' { $result = $result -and (-not $clauseMatch) }
            }
        }

        if (-not $result) { return }

        if ($Highlight -and $Mode -ne 'Fuzzy') {
            $rendered = Format-FindObjectHighlight -Text $value -Keywords $positiveKeywords -CaseSensitive $CaseSensitive
            Write-Host "  * $rendered"
        }

        Write-Output $InputObject
    }
}

# Create aliases
New-Alias -Name fob -Value Find-ObjectByName -Force

# Export the functions and aliases
Export-ModuleMember -Function Find-ObjectByName, Get-FindObjectConfig, Set-FindObjectConfig -Alias fob
