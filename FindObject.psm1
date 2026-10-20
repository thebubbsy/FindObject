#Requires -Version 5.1

#region Configuration

$script:FindObjectConfigPath = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'FindObject\config.json'

$script:FindObjectConfig = @{
    Mode          = 'Contains'   # Contains | StartsWith | Fuzzy | Exact | Regex
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
        Write-Verbose "FindObject: could not load saved config from '$script:FindObjectConfigPath': $_"
    }
}

function Get-FindObjectConfig {
    <#
    .SYNOPSIS
        Returns the current default settings used by Find-ObjectByName.

    .DESCRIPTION
        Displays the session defaults for Mode, Property, CaseSensitive, and Highlight.
        These are used by Find-ObjectByName whenever the corresponding parameter is not
        explicitly supplied. Defaults can be changed with Set-FindObjectConfig and
        optionally persisted across sessions.

    .EXAMPLE
        Get-FindObjectConfig

        Mode       : Contains
        Property   : Name
        CaseSensitive : False
        Highlight  : False

    .LINK
        Set-FindObjectConfig
        Find-ObjectByName
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    [PSCustomObject]$script:FindObjectConfig
}

function Set-FindObjectConfig {
    <#
    .SYNOPSIS
        Changes the default settings used by Find-ObjectByName.

    .DESCRIPTION
        Sets session-level defaults for Mode, Property, CaseSensitive, and/or Highlight.
        Use -Persist to also write the settings to disk so they apply in future sessions.

    .PARAMETER Mode
        Default matching mode: Contains, StartsWith, Fuzzy, Exact, or Regex.

    .PARAMETER Property
        Default property name to match against.

    .PARAMETER CaseSensitive
        Enable case-sensitive matching by default.

    .PARAMETER Highlight
        Enable colorized console preview by default.

    .PARAMETER Persist
        Save settings to disk for future sessions.

    .EXAMPLE
        Set-FindObjectConfig -Mode Fuzzy -Highlight -Persist

    .LINK
        Get-FindObjectConfig
        Find-ObjectByName
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [ValidateSet('Contains', 'StartsWith', 'Fuzzy', 'Exact', 'Regex')]
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

function Test-FuzzyMatch {
    <# Subsequence match: every char of $Pattern appears in $Text in order. #>
    param([string]$Text, [string]$Pattern, [System.StringComparison]$Comparison)

    if ($Pattern.Length -eq 0) { return $true }
    if ($Text.Length -eq 0) { return $false }

    $cursor = 0
    $len = $Text.Length
    for ($i = 0; $i -lt $Pattern.Length; $i++) {
        $idx = $Text.IndexOf($Pattern[$i].ToString(), $cursor, $Comparison)
        if ($idx -lt 0) { return $false }
        $cursor = $idx + 1
        if ($cursor -ge $len -and $i -lt $Pattern.Length - 1) { return $false }
    }
    return $true
}

function ConvertTo-FindObjectTokens {
    <#
    Tokenizes -SearchTerms into a stream of tokens:
    Literal (quoted phrases preserved, outer quotes stripped), LParen '(', RParen ')',
    And ('AND', '-and', '&&'), Or ('OR', '-or', '||'), and Not ('NOT', '-not', '!').
    #>
    param(
        [string[]]$SearchTerms,
        [string]$Mode = 'Contains'
    )

    $tokens = [System.Collections.Generic.List[hashtable]]::new()
    if ($null -eq $SearchTerms) { return , $tokens }

    # If in Exact or Regex mode and single term without explicit boolean operators, treat as single literal
    if (($Mode -eq 'Exact' -or $Mode -eq 'Regex') -and $SearchTerms.Count -eq 1) {
        $single = $SearchTerms[0]
        if ($null -ne $single -and -not [string]::IsNullOrWhiteSpace($single)) {
            $trimmed = $single.Trim()
            $hasBoolOps = ($trimmed -match '(?i)(^|\s)(and|or|-and|-or|&&|\|\|)(\s|$)' -or $trimmed -match '(?i)(^|\s)(not|-not|!)(\s|\()')
            if (-not $hasBoolOps) {
                $quotedFlag = $false
                if ($Mode -eq 'Exact' -and $trimmed.Length -ge 2 -and (
                    ($trimmed.StartsWith('"') -and $trimmed.EndsWith('"')) -or
                    ($trimmed.StartsWith("'") -and $trimmed.EndsWith("'"))
                )) {
                    $q = $trimmed[0]
                    $inner = $trimmed.Substring(1, $trimmed.Length - 2)
                    $trimmed = $inner.Replace("$q$q", "$q")
                    $quotedFlag = $true
                }
                $tokens.Add(@{ Type = 'Literal'; Value = $trimmed; Quoted = $quotedFlag })
                return , $tokens
            }
        }
    }

    foreach ($term in $SearchTerms) {
        if ($null -eq $term -or [string]::IsNullOrWhiteSpace($term)) { continue }
        $str = $term.Trim()
        $len = $str.Length
        $i = 0

        while ($i -lt $len) {
            # Skip whitespace
            while ($i -lt $len -and [char]::IsWhiteSpace($str[$i])) { $i++ }
            if ($i -ge $len) { break }

            $ch = $str[$i]

            # Grouping parentheses
            if ($ch -eq '(') {
                $tokens.Add(@{ Type = 'LParen' })
                $i++
                continue
            }
            if ($ch -eq ')') {
                $tokens.Add(@{ Type = 'RParen' })
                $i++
                continue
            }

            # Quoted strings: double or single quotes
            if ($ch -eq '"' -or $ch -eq "'") {
                $quoteChar = $ch
                $i++
                $sb = [System.Text.StringBuilder]::new()
                $closed = $false
                while ($i -lt $len) {
                    if ($str[$i] -eq $quoteChar) {
                        # Escaped quote inside quotes ("" or '')
                        if ($i + 1 -lt $len -and $str[$i + 1] -eq $quoteChar) {
                            [void]$sb.Append($quoteChar)
                            $i += 2
                        } else {
                            $i++ # Consume closing quote
                            $closed = $true
                            break
                        }
                    } else {
                        [void]$sb.Append($str[$i])
                        $i++
                    }
                }
                if (-not $closed) {
                    throw "Unclosed quote in search term: $term"
                }
                $val = $sb.ToString()
                if (-not [string]::IsNullOrWhiteSpace($val)) {
                    $tokens.Add(@{ Type = 'Literal'; Value = $val; Quoted = $true })
                }
                continue
            }

            # Two-character operators: &&, ||
            if ($i + 1 -lt $len) {
                $two = $str.Substring($i, 2)
                if ($two -eq '&&') {
                    $tokens.Add(@{ Type = 'And' })
                    $i += 2
                    continue
                }
                if ($two -eq '||') {
                    $tokens.Add(@{ Type = 'Or' })
                    $i += 2
                    continue
                }
            }

            # Single-character operator: !
            if ($ch -eq '!') {
                $tokens.Add(@{ Type = 'Not' })
                $i++
                continue
            }

            # Bare word / keyword
            $start = $i
            while ($i -lt $len) {
                $c = $str[$i]
                if ([char]::IsWhiteSpace($c) -or $c -eq '(' -or $c -eq ')') {
                    break
                }
                if (($c -eq '"' -or $c -eq "'") -and $Mode -ne 'Regex') {
                    break
                }
                if ($c -eq '!' -and $i -gt $start) { break }
                if (($c -eq '&' -or $c -eq '|') -and $i + 1 -lt $len) {
                    $peek2 = $str.Substring($i, 2)
                    if ($peek2 -eq '&&' -or $peek2 -eq '||') { break }
                }
                $i++
            }

            $word = $str.Substring($start, $i - $start)
            if ([string]::IsNullOrEmpty($word)) { continue }

            if ($word -ieq 'and' -or $word -ieq '-and') {
                $tokens.Add(@{ Type = 'And' })
            } elseif ($word -ieq 'or' -or $word -ieq '-or') {
                $tokens.Add(@{ Type = 'Or' })
            } elseif ($word -ieq 'not' -or $word -ieq '-not') {
                $tokens.Add(@{ Type = 'Not' })
            } else {
                $tokens.Add(@{ Type = 'Literal'; Value = $word; Quoted = $false })
            }
        }
    }

    return , $tokens
}

function ConvertTo-FindObjectAst {
    <#
    Parses tokens or search terms into an Abstract Syntax Tree (AST) enforcing
    operator precedence NOT > AND > OR, parentheses grouping, and unary NOT.
    Grammar:
      FilterExpr := OrExpr ( 'NOT' UnaryExpr )*
      OrExpr     := AndExpr ( ('OR' | implicit-OR) AndExpr )*
      AndExpr    := UnaryExpr ( 'AND' UnaryExpr )*
      UnaryExpr  := 'NOT' UnaryExpr | PrimaryExpr
      PrimaryExpr:= '(' FilterExpr ')' | Literal
    #>
    param(
        [string[]]$SearchTerms,
        [hashtable[]]$Tokens,
        [string]$Mode = 'Contains'
    )

    if ($null -ne $SearchTerms -and $SearchTerms.Count -gt 0) {
        $Tokens = ConvertTo-FindObjectTokens -SearchTerms $SearchTerms -Mode $Mode
    }

    if ($null -eq $Tokens -or $Tokens.Count -eq 0) {
        throw "No valid search keywords found. Provide at least one keyword (operators like 'and'/'or'/'not' alone are not sufficient)."
    }

    $hasLiteral = $false
    foreach ($t in $Tokens) {
        if ($t.Type -eq 'Literal') { $hasLiteral = $true; break }
    }
    if (-not $hasLiteral) {
        throw "No valid search keywords found. Provide at least one keyword (operators like 'and'/'or'/'not' alone are not sufficient)."
    }

    $cursor = [int[]]@(0)

    function Peek {
        if ($cursor[0] -lt $Tokens.Count) { return $Tokens[$cursor[0]] }
        return $null
    }

    function Consume {
        if ($cursor[0] -lt $Tokens.Count) {
            $t = $Tokens[$cursor[0]]
            $cursor[0]++
            return $t
        }
        return $null
    }

    function parseFilterExpr {
        $node = parseOrExpr
        while ($true) {
            $tok = Peek
            if ($null -ne $tok -and $tok.Type -eq 'Not') {
                $null = Consume
                $child = parseUnaryExpr
                $node = @{ Type = 'And'; Left = $node; Right = @{ Type = 'Not'; Child = $child } }
            } else {
                break
            }
        }
        return $node
    }

    function parseOrExpr {
        $node = parseAndExpr
        while ($true) {
            $tok = Peek
            if ($null -eq $tok) { break }
            if ($tok.Type -eq 'Or') {
                $null = Consume
                $right = parseAndExpr
                $node = @{ Type = 'Or'; Left = $node; Right = $right }
            } elseif ($tok.Type -in @('Literal', 'LParen')) {
                # Adjacent primary expressions default to implicit OR
                $right = parseAndExpr
                $node = @{ Type = 'Or'; Left = $node; Right = $right }
            } else {
                break
            }
        }
        return $node
    }

    function parseAndExpr {
        $node = parseUnaryExpr
        while ($true) {
            $tok = Peek
            if ($null -eq $tok) { break }
            if ($tok.Type -eq 'And') {
                $null = Consume
                $right = parseUnaryExpr
                $node = @{ Type = 'And'; Left = $node; Right = $right }
            } else {
                break
            }
        }
        return $node
    }

    function parseUnaryExpr {
        $tok = Peek
        if ($null -ne $tok -and $tok.Type -eq 'Not') {
            $null = Consume
            $child = parseUnaryExpr
            return @{ Type = 'Not'; Child = $child }
        }
        return (parsePrimaryExpr)
    }

    function parsePrimaryExpr {
        $tok = Peek
        if ($null -eq $tok) {
            throw "Unexpected end of expression."
        }
        if ($tok.Type -eq 'LParen') {
            $null = Consume
            $expr = parseFilterExpr
            $closing = Peek
            if ($null -eq $closing -or $closing.Type -ne 'RParen') {
                throw "Unclosed parenthesis in search expression."
            }
            $null = Consume
            return $expr
        }
        if ($tok.Type -eq 'Literal') {
            $lit = Consume
            return @{ Type = 'Literal'; Value = $lit.Value; Quoted = $lit.Quoted; Regex = $null }
        }
        throw "Unexpected token '$($tok.Type)' in expression."
    }

    $ast = parseFilterExpr
    if ($cursor[0] -lt $Tokens.Count) {
        $rem = $Tokens[$cursor[0]]
        throw "Unexpected token '$($rem.Type)' at position $($cursor[0])."
    }
    return $ast
}

function Get-FindObjectLiterals {
    <#
    Extracts all Literal nodes from the AST.
    When -PositiveOnly is specified, literals under 'Not' nodes are excluded.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Node,

        [switch]$PositiveOnly
    )

    $results = [System.Collections.Generic.List[hashtable]]::new()
    if ($null -eq $Node) { return , $results }
    $onlyPositive = $PositiveOnly.IsPresent

    function collectLiterals {
        param([hashtable]$n, [bool]$isNegated)

        if ($null -eq $n) { return }

        switch ($n.Type) {
            'Literal' {
                if (-not ($onlyPositive -and $isNegated)) {
                    $results.Add($n)
                }
            }
            'Not' {
                collectLiterals -n $n.Child -isNegated (-not $isNegated)
            }
            'And' {
                collectLiterals -n $n.Left -isNegated $isNegated
                collectLiterals -n $n.Right -isNegated $isNegated
            }
            'Or' {
                collectLiterals -n $n.Left -isNegated $isNegated
                collectLiterals -n $n.Right -isNegated $isNegated
            }
        }
    }

    collectLiterals -n $Node -isNegated $false
    return , $results
}

function Test-FindObjectAstValues {
    <#
    Evaluates an AST node against candidate string values.
    An object satisfies a Literal if ANY candidate value matches the literal.
    Boolean operators (AND, OR, NOT) evaluate over the object as a whole.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Node,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$Values,

        [string]$Mode = 'Contains',
        [System.StringComparison]$Comparison = [System.StringComparison]::OrdinalIgnoreCase,
        [int]$FuzzyThreshold = 0
    )

    switch ($Node.Type) {
        'Literal' {
            if ($null -ne $Node.Regex) {
                foreach ($val in $Values) {
                    if ([string]::IsNullOrEmpty($val)) { continue }
                    if ($Node.Regex.IsMatch($val)) { return $true }
                }
                return $false
            }

            foreach ($val in $Values) {
                if ([string]::IsNullOrEmpty($val)) { continue }
                $matched = switch ($Mode) {
                    'Contains'   { $val.IndexOf($Node.Value, $Comparison) -ge 0 }
                    'StartsWith' { $val.StartsWith($Node.Value, $Comparison) }
                    'Fuzzy'      { Test-FuzzyMatch -Text $val -Pattern $Node.Value -Comparison $Comparison }
                    'Exact'      { $val.Equals($Node.Value, $Comparison) }
                    'Regex'      {
                        $opt = if ($Comparison -eq [System.StringComparison]::Ordinal) {
                            [System.Text.RegularExpressions.RegexOptions]::None
                        } else {
                            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
                        }
                        [System.Text.RegularExpressions.Regex]::IsMatch($val, $Node.Value, $opt)
                    }
                    default { $val.IndexOf($Node.Value, $Comparison) -ge 0 }
                }
                if ($matched) { return $true }
            }
            return $false
        }
        'Not' {
            $childResult = Test-FindObjectAstValues -Node $Node.Child -Values $Values -Mode $Mode -Comparison $Comparison -FuzzyThreshold $FuzzyThreshold
            return (-not $childResult)
        }
        'And' {
            $leftResult = Test-FindObjectAstValues -Node $Node.Left -Values $Values -Mode $Mode -Comparison $Comparison -FuzzyThreshold $FuzzyThreshold
            if (-not $leftResult) { return $false }
            return (Test-FindObjectAstValues -Node $Node.Right -Values $Values -Mode $Mode -Comparison $Comparison -FuzzyThreshold $FuzzyThreshold)
        }
        'Or' {
            $leftResult = Test-FindObjectAstValues -Node $Node.Left -Values $Values -Mode $Mode -Comparison $Comparison -FuzzyThreshold $FuzzyThreshold
            if ($leftResult) { return $true }
            return (Test-FindObjectAstValues -Node $Node.Right -Values $Values -Mode $Mode -Comparison $Comparison -FuzzyThreshold $FuzzyThreshold)
        }
        default {
            return $false
        }
    }
}

function Test-FindObjectAst {
    <#
    Evaluates an AST node against a candidate string value with short-circuiting.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Node,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value,

        [string]$Mode = 'Contains',
        [System.StringComparison]$Comparison = [System.StringComparison]::OrdinalIgnoreCase,
        [int]$FuzzyThreshold = 0
    )

    return (Test-FindObjectAstValues -Node $Node -Values @($Value) -Mode $Mode -Comparison $Comparison -FuzzyThreshold $FuzzyThreshold)
}

function Get-FindObjectCandidateValues {
    <#
    Extracts all searchable candidate string values from an InputObject.
    Supports dotted property paths (Nested.Deep), collection unwrapping,
    wildcard multi-property conversion (-Property *), and element-by-element arrays.
    #>
    param(
        [Parameter(Mandatory = $true)]
        $InputObject,

        [string]$Property = 'Name',
        [switch]$AsString,
        [switch]$SearchAllProperties
    )

    $values = [System.Collections.Generic.List[string]]::new()

    if ($null -eq $InputObject) { return , $values }

    if ($AsString) {
        $values.Add([string]$InputObject)
        return , $values
    }

    if ($SearchAllProperties) {
        if ($null -ne $InputObject.PSObject) {
            foreach ($prop in $InputObject.PSObject.Properties) {
                $val = $prop.Value
                if ($null -eq $val) { continue }
                if ($val -is [System.Collections.IEnumerable] -and $val -isnot [string]) {
                    foreach ($item in $val) {
                        if ($null -ne $item) {
                            $s = [string]$item
                            if ($s.Length -gt 0) { $values.Add($s) }
                        }
                    }
                } else {
                    $s = [string]$val
                    if ($s.Length -gt 0) { $values.Add($s) }
                }
            }
        }
        return , $values
    }

    # Specific property targeting
    $hasDirect = $false
    $raw = $null
    if ($null -ne $InputObject.PSObject -and $null -ne $InputObject.PSObject.Properties[$Property]) {
        $raw = $InputObject.PSObject.Properties[$Property].Value
        $hasDirect = $true
    } elseif ($null -ne $InputObject.$Property) {
        $raw = $InputObject.$Property
        $hasDirect = $true
    }

    if (-not $hasDirect -and $Property -match '\.') {
        $segments = $Property -split '\.'
        $currentObjects = @($InputObject)
        foreach ($segment in $segments) {
            $nextObjects = [System.Collections.Generic.List[object]]::new()
            foreach ($obj in $currentObjects) {
                if ($null -eq $obj) { continue }
                $pVal = $null
                if ($null -ne $obj.PSObject -and $null -ne $obj.PSObject.Properties[$segment]) {
                    $pVal = $obj.PSObject.Properties[$segment].Value
                } elseif ($null -ne $obj.$segment) {
                    $pVal = $obj.$segment
                }
                if ($null -eq $pVal) { continue }
                if ($pVal -is [System.Collections.IEnumerable] -and $pVal -isnot [string]) {
                    foreach ($elem in $pVal) {
                        if ($null -ne $elem) { $nextObjects.Add($elem) }
                    }
                } else {
                    $nextObjects.Add($pVal)
                }
            }
            $currentObjects = $nextObjects
        }
        $raw = $currentObjects
    }

    if ($null -eq $raw) { return , $values }

    if ($raw -is [System.Collections.IEnumerable] -and $raw -isnot [string]) {
        $hasItems = $false
        foreach ($item in $raw) {
            if ($null -ne $item) {
                $s = [string]$item
                if ($s.Length -gt 0) {
                    $values.Add($s)
                    $hasItems = $true
                }
            }
        }
        if (-not $hasItems) {
            $values.Add("")
        }
    } else {
        $s = [string]$raw
        if (-not [string]::IsNullOrWhiteSpace($s)) {
            $values.Add($s)
        }
    }

    return , $values
}

function ConvertTo-FindObjectClauses {
    <#
    Backward-compatible wrapper for AST root node.
    #>
    param([string[]]$SearchTerms)

    return ConvertTo-FindObjectAst -SearchTerms $SearchTerms
}

function Format-FindObjectHighlight {
    <# Wraps keyword or regex occurrences in ANSI bold-yellow for terminal display. #>
    param(
        [string]$Text,
        [string[]]$Keywords,
        [System.StringComparison]$Comparison,
        [string]$Mode = 'Contains'
    )

    $ranges = [System.Collections.Generic.List[object]]::new()

    foreach ($keyword in $Keywords) {
        if ([string]::IsNullOrEmpty($keyword)) { continue }
        if ($Mode -eq 'Regex') {
            $rxOpts = if ($Comparison -eq [System.StringComparison]::Ordinal) {
                [System.Text.RegularExpressions.RegexOptions]::None
            } else {
                [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
            }
            try {
                $rxMatches = [System.Text.RegularExpressions.Regex]::Matches($Text, $keyword, $rxOpts)
                foreach ($m in $rxMatches) {
                    if ($m.Success -and $m.Length -gt 0) {
                        $ranges.Add(@{ Start = $m.Index; End = $m.Index + $m.Length })
                    }
                }
            } catch {}
        } else {
            $searchFrom = 0
            while ($searchFrom -lt $Text.Length) {
                $idx = $Text.IndexOf($keyword, $searchFrom, $Comparison)
                if ($idx -lt 0) { break }
                $ranges.Add(@{ Start = $idx; End = $idx + $keyword.Length })
                $searchFrom = $idx + [Math]::Max(1, $keyword.Length)
            }
        }
    }

    if ($ranges.Count -eq 0) { return $Text }

    $sorted = $ranges | Sort-Object { $_.Start }
    $esc = [char]27
    $boldYellow = "${esc}[1;33m"
    $reset = "${esc}[0m"
    $sb = [System.Text.StringBuilder]::new($Text.Length + ($ranges.Count * 12))
    $cursor = 0

    foreach ($range in $sorted) {
        if ($range.Start -lt $cursor) { continue }
        [void]$sb.Append($Text, $cursor, $range.Start - $cursor)
        [void]$sb.Append($boldYellow).Append($Text, $range.Start, $range.End - $range.Start).Append($reset)
        $cursor = $range.End
    }
    [void]$sb.Append($Text, $cursor, $Text.Length - $cursor)

    return $sb.ToString()
}

#endregion

function Find-ObjectByName {
    <#
    .SYNOPSIS
        Filters pipeline objects by keyword with AND/OR/NOT logic and multiple matching modes.

    .DESCRIPTION
        The object-aware grep that PowerShell should have shipped with.

        Accepts objects from the pipeline and keeps only those whose target property (or string
        representation) matches the given search terms. Keywords support AND, OR, and NOT logic
        in both natural-language ("chrome OR firefox NOT helper") and array ("chrome","or","firefox")
        syntax.

        Matching modes:
          - Contains   : substring match (default) — uses [String]::Contains for speed
          - StartsWith : prefix match — uses [String]::StartsWith
          - Fuzzy      : subsequence match ("fnd" matches "FindObject")
          - Exact      : full string equality
          - Regex      : .NET regular expression

        By default matches the 'Name' property. Use -Property to target any property, -Property *
        to search all string properties, or -AsString to match the object's ToString() output.

        Performance: uses direct BCL string methods (Contains/StartsWith/IndexOf) instead of
        wildcard pattern matching, delivering 5-20x throughput on large pipelines compared to
        equivalent Where-Object { $_.Name -like '*x*' } expressions.

    .PARAMETER SearchTerms
        One or more keywords, optionally combined with 'and', 'or', 'not'. Accepts both a single
        natural-language string ("test AND file NOT backup") and array elements ("test","and","file").

    .PARAMETER InputObject
        Objects to filter. Accepts pipeline input.

    .PARAMETER Mode
        Matching algorithm: Contains (default), StartsWith, Fuzzy, Exact, or Regex.
        Falls back to the value from Get-FindObjectConfig when not specified.

    .PARAMETER Property
        Property to match against. Defaults to 'Name'. Use '*' to search all string-typed
        properties on each object.

    .PARAMETER AsString
        Match against the object's ToString() representation instead of a named property.
        Ideal for plain strings or objects without a useful Name property.

    .PARAMETER CaseSensitive
        Perform case-sensitive comparison. Off by default.

    .PARAMETER Highlight
        Print a colorized preview to the console (matched text in bold yellow) while still
        passing the original objects through the pipeline unchanged.

    .PARAMETER Summary
        Display a colorized console telemetry HUD summary bar at the end of pipeline execution
        showing matched vs. scanned count, hit rate bar, active mode/property, and elapsed ms.

    .PARAMETER First
        Stop after emitting this many matches. Enables early pipeline termination for
        significant performance gains on large input sets.

    .PARAMETER Skip
        Skip this many initial matches before emitting results.

    .PARAMETER Count
        Return only the number of matching objects instead of the objects themselves.

    .PARAMETER Quiet
        Return $true if at least one object matches, $false otherwise. Stops processing
        after the first match for maximum speed.

    .EXAMPLE
        Get-Process | fob "chrome OR firefox NOT helper"

        Finds Chrome and Firefox processes, excluding helper processes.

    .EXAMPLE
        Get-ChildItem -Recurse | fob ".ps1 NOT backup" -First 10

        First 10 PowerShell scripts that don't contain "backup" in the name.

    .EXAMPLE
        Get-Service | fob "sql" -Property DisplayName -Highlight -Summary

        Services with "sql" in their display name, with colorized output and a telemetry summary HUD.

    .EXAMPLE
        Get-Process | fob "crome" -Mode Fuzzy

        Fuzzy match: "crome" matches "chrome.exe" (characters in order, not contiguous).

    .EXAMPLE
        "apple pie", "banana bread" | fob "pie" -AsString

        Match plain strings directly.

    .EXAMPLE
        Get-ChildItem | fob "report" -Count

        Returns the number of files with "report" in the name.

    .EXAMPLE
        Get-Process | fob "nonexistent" -Quiet

        Returns $false without enumerating all matches.

    .INPUTS
        System.Management.Automation.PSObject

    .OUTPUTS
        System.Management.Automation.PSObject
        System.Int32 (when -Count is used)
        System.Boolean (when -Quiet is used)

    .LINK
        Where-Object
        Select-String
        Get-FindObjectConfig
        Set-FindObjectConfig

    .NOTES
        Author: Matthew Bubb
        Repository: https://github.com/thebubbsy/FindObject

        Objects without the target property (or with a null/empty value) are silently skipped.
        Comparison is case-insensitive unless -CaseSensitive is specified.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    [Alias('fob')]
    [OutputType([PSObject])]
    [OutputType([int], ParameterSetName = 'Count')]
    [OutputType([bool], ParameterSetName = 'Quiet')]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [Alias('FilterString')]
        [ValidateNotNullOrEmpty()]
        [string[]]$SearchTerms,

        [Parameter(ValueFromPipeline = $true)]
        [psobject]$InputObject,

        [ValidateSet('Contains', 'StartsWith', 'Fuzzy', 'Exact', 'Regex')]
        [string]$Mode,

        [string]$Property,

        [switch]$AsString,

        [switch]$CaseSensitive,

        [switch]$Highlight,

        [Alias('Stats')]
        [switch]$Summary,

        [switch]$CopyMatches,

        [Alias('CopyMd')]
        [switch]$CopyMarkdown,

        [switch]$CopyCsv,

        [switch]$CopyTsv,

        [switch]$CopyJson,

        [Alias('CopyTypes')]
        [switch]$CopyTypeSummary,

        [Alias('CopyTypesTsv')]
        [switch]$CopyTypeTsv,

        [Alias('CopyTypesJson')]
        [switch]$CopyTypeJson,

        [Alias('CopyReport', 'CopyStats')]
        [switch]$CopySummary,

        [Alias('CopyReportJson', 'CopyStatsJson')]
        [switch]$CopySummaryJson,

        [Alias('CopyReportTsv', 'CopyStatsTsv')]
        [switch]$CopySummaryTsv,

        [Alias('CopyReportCsv', 'CopyStatsCsv')]
        [switch]$CopySummaryCsv,

        [Alias('NotMatch', 'v')]
        [switch]$Invert,

        [Alias('u')]
        [switch]$Unique,

        [Parameter(ParameterSetName = 'Default')]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$First,

        [Parameter(ParameterSetName = 'Default')]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Skip,

        [Parameter(ParameterSetName = 'Count', Mandatory = $true)]
        [switch]$Count,

        [Parameter(ParameterSetName = 'Quiet', Mandatory = $true)]
        [switch]$Quiet
    )

    begin {
        $script:foStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        # Resolve defaults from config
        if (-not $PSBoundParameters.ContainsKey('Mode')) { $Mode = $script:FindObjectConfig.Mode }
        if (-not $PSBoundParameters.ContainsKey('Property')) { $Property = $script:FindObjectConfig.Property }
        if (-not $PSBoundParameters.ContainsKey('CaseSensitive')) { $CaseSensitive = [bool]$script:FindObjectConfig.CaseSensitive }
        if (-not $PSBoundParameters.ContainsKey('Highlight')) { $Highlight = [bool]$script:FindObjectConfig.Highlight }

        # Pre-compute comparison type once — avoids per-object branching
        $comparison = if ($CaseSensitive) {
            [System.StringComparison]::Ordinal
        } else {
            [System.StringComparison]::OrdinalIgnoreCase
        }

        # Parse search terms into AST
        $ast = ConvertTo-FindObjectAst -SearchTerms $SearchTerms -Mode $Mode
        $allLiterals = Get-FindObjectLiterals -Node $ast
        $positiveKeywords = @(Get-FindObjectLiterals -Node $ast -PositiveOnly | ForEach-Object { $_.Value })

        # Pre-compile regex patterns if in Regex mode
        $regexOptions = if ($CaseSensitive) { [System.Text.RegularExpressions.RegexOptions]::None } else { [System.Text.RegularExpressions.RegexOptions]::IgnoreCase }
        if ($Mode -eq 'Regex') {
            try {
                foreach ($literal in $allLiterals) {
                    $literal.Regex = [System.Text.RegularExpressions.Regex]::new($literal.Value, $regexOptions)
                }
            } catch {
                throw "FindObject: Invalid regular expression pattern: $($_.Exception.Message)"
            }
        }

        $clauseCount = $allLiterals.Count
        $searchAllProperties = ($Property -eq '*')

        # Counters for -First / -Skip / -Count / -Quiet / verbose stats
        $script:foMatchCount = 0
        $script:foEmitted = 0
        $script:foProcessed = 0
        $script:foSkipped = 0
        $script:foDuplicatesFiltered = 0
        $script:foDone = $false
        $script:foSeenSet = $null
        if ($Unique) {
            $strComparer = if ($CaseSensitive) { [System.StringComparer]::Ordinal } else { [System.StringComparer]::OrdinalIgnoreCase }
            $script:foSeenSet = [System.Collections.Generic.HashSet[string]]::new($strComparer)
        }
        $script:foCopiedValues = $null
        if ($CopyMatches) { $script:foCopiedValues = [System.Collections.Generic.List[string]]::new() }
        $script:foMarkdownRows = $null
        if ($CopyMarkdown) { $script:foMarkdownRows = [System.Collections.Generic.List[string]]::new() }
        $script:foCsvRows = $null
        if ($CopyCsv) { $script:foCsvRows = [System.Collections.Generic.List[string]]::new() }
        $script:foTsvRows = $null
        if ($CopyTsv) { $script:foTsvRows = [System.Collections.Generic.List[string]]::new() }
        $script:foJsonItems = $null
        if ($CopyJson) { $script:foJsonItems = [System.Collections.Generic.List[object]]::new() }
        $script:foTypeCounts = $null
        if ($Summary -or $CopyTypeSummary -or $CopyTypeTsv -or $CopyTypeJson -or $CopySummary -or $CopySummaryJson -or $CopySummaryTsv -or $CopySummaryCsv) {
            $script:foTypeCounts = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::OrdinalIgnoreCase)
        }
        $script:foSampleValues = $null
        if ($Summary -or $CopySummary -or $CopySummaryJson -or $CopySummaryTsv -or $CopySummaryCsv) { $script:foSampleValues = [System.Collections.Generic.List[string]]::new() }

        Write-Verbose "FindObject: Mode=$Mode Property=$Property CaseSensitive=$CaseSensitive Clauses=$clauseCount Invert=$Invert Unique=$Unique"
    }

    process {
        if ($script:foDone) { return }
        if ($null -eq $InputObject) { return }
        $script:foProcessed++

        # --- Resolve the candidate value(s) to test ---
        $values = Get-FindObjectCandidateValues -InputObject $InputObject -Property $Property -AsString:$AsString -SearchAllProperties:$searchAllProperties
        if ($values.Count -eq 0 -and -not $AsString) { return }

        # --- Evaluate AST against candidate values ---
        $result = Test-FindObjectAstValues -Node $ast -Values $values -Mode $Mode -Comparison $comparison
        if ($Invert) { $result = -not $result }
        if (-not $result) { return }

        if ($Unique -and $null -ne $script:foSeenSet) {
            $dedupKey = if ($values.Count -gt 0) { ($values -join '|') } else { [string]$InputObject }
            if (-not $script:foSeenSet.Add($dedupKey)) {
                $script:foDuplicatesFiltered++
                return
            }
        }

        $script:foMatchCount++

        # -Quiet: we have our answer
        if ($Quiet) {
            $script:foDone = $true
            return
        }

        # -Skip: discard early matches
        if ($Skip -and $script:foMatchCount -le $Skip) {
            $script:foSkipped++
            return
        }

        # -Count: just tally
        if ($Count) { return }

        if ($null -ne $script:foTypeCounts) {
            $tName = if ($null -ne $InputObject) { $InputObject.GetType().Name } else { 'Object' }
            if ($script:foTypeCounts.ContainsKey($tName)) {
                $script:foTypeCounts[$tName] = $script:foTypeCounts[$tName] + 1
            } else {
                $script:foTypeCounts[$tName] = 1
            }
        }

        if ($CopyMatches -and $null -ne $script:foCopiedValues) {
            $valToCopy = if ($values.Count -gt 0) { [string]$values[0] } else { [string]$InputObject }
            $script:foCopiedValues.Add($valToCopy)
        }
        if ($CopyMarkdown -and $null -ne $script:foMarkdownRows -and $script:foMarkdownRows.Count -lt 500) {
            $valCell = if ($values.Count -gt 0) { [string]$values[0] } else { [string]$InputObject }
            $valCell = ($valCell -replace '\|', '\|' -replace '\r?\n', ' ').Trim()
            $propCell = if ($AsString) { 'ToString()' } else { $Property }
            $typeCell = if ($null -ne $InputObject) { $InputObject.GetType().Name } else { 'Object' }
            $rowIdx = $script:foMarkdownRows.Count + 1
            $script:foMarkdownRows.Add("| $rowIdx | ``$propCell`` | $valCell | ``$typeCell`` |")
        }
        if ($CopyCsv -and $null -ne $script:foCsvRows -and $script:foCsvRows.Count -lt 500) {
            $valCell = if ($values.Count -gt 0) { [string]$values[0] } else { [string]$InputObject }
            $safeVal = ($valCell -replace '\r?\n', ' ').Replace('"', '""').Trim()
            $propCell = if ($AsString) { 'ToString()' } else { $Property }
            $safeProp = ([string]$propCell).Replace('"', '""')
            $typeCell = if ($null -ne $InputObject) { $InputObject.GetType().Name } else { 'Object' }
            $rowIdx = $script:foCsvRows.Count + 1
            $script:foCsvRows.Add("$rowIdx,`"$safeProp`",`"$safeVal`",`"$typeCell`"")
        }
        if ($CopyTsv -and $null -ne $script:foTsvRows -and $script:foTsvRows.Count -lt 500) {
            $valCell = if ($values.Count -gt 0) { [string]$values[0] } else { [string]$InputObject }
            $safeVal = ($valCell -replace "[\t\r\n]+", ' ').Trim()
            $propCell = if ($AsString) { 'ToString()' } else { $Property }
            $safeProp = (([string]$propCell) -replace "[\t\r\n]+", ' ').Trim()
            $typeCell = if ($null -ne $InputObject) { $InputObject.GetType().Name } else { 'Object' }
            $rowIdx = $script:foTsvRows.Count + 1
            $script:foTsvRows.Add("$rowIdx`t$safeProp`t$safeVal`t$typeCell")
        }
        if ($CopyJson -and $null -ne $script:foJsonItems -and $script:foJsonItems.Count -lt 500) {
            $valCell = if ($values.Count -gt 0) { [string]$values[0] } else { [string]$InputObject }
            $propCell = if ($AsString) { 'ToString()' } else { $Property }
            $typeCell = if ($null -ne $InputObject) { $InputObject.GetType().Name } else { 'Object' }
            $rowIdx = $script:foJsonItems.Count + 1
            $script:foJsonItems.Add([PSCustomObject]@{
                Index        = $rowIdx
                Property     = $propCell
                MatchedValue = $valCell
                Type         = $typeCell
            })
        }
        if (($Summary -or $CopySummary -or $CopySummaryJson -or $CopySummaryTsv -or $CopySummaryCsv) -and $null -ne $script:foSampleValues -and $script:foSampleValues.Count -lt 3) {
            $sampleVal = if ($values.Count -gt 0) { [string]$values[0] } else { [string]$InputObject }
            if (-not [string]::IsNullOrWhiteSpace($sampleVal)) { $script:foSampleValues.Add($sampleVal) }
        }

        # -Highlight: in-band ANSI formatting emitted cleanly to pipeline stream
        $outputObject = $InputObject
        if ($Highlight -and $Mode -ne 'Fuzzy' -and -not $Invert) {
            $targetProp = if ([string]::IsNullOrEmpty($Property) -or $Property -eq '*') { 'Name' } else { $Property }
            if (-not $AsString -and $null -ne $InputObject.PSObject -and $null -ne $InputObject.PSObject.Properties[$targetProp]) {
                try {
                    $clone = [PSCustomObject]@{}
                    foreach ($p in $InputObject.PSObject.Properties) {
                        $clone | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value
                    }
                    $origVal = [string]$clone.$targetProp
                    $clone.$targetProp = Format-FindObjectHighlight -Text $origVal -Keywords $positiveKeywords -Comparison $comparison -Mode $Mode
                    $outputObject = $clone
                } catch {
                    try {
                        $InputObject.$targetProp = Format-FindObjectHighlight -Text ([string]$InputObject.$targetProp) -Keywords $positiveKeywords -Comparison $comparison -Mode $Mode
                    } catch {}
                }
            }
        }

        $script:foEmitted++
        Write-Output $outputObject

        # -First: early termination
        if ($First -and $script:foEmitted -ge $First) {
            $script:foDone = $true
        }
    }

    end {
        if ($script:foStopwatch) { $script:foStopwatch.Stop() }
        $elapsedMs = if ($script:foStopwatch) { [Math]::Round($script:foStopwatch.Elapsed.TotalMilliseconds, 1) } else { 0 }
        $ratePerSec = if ($script:foStopwatch -and $script:foStopwatch.Elapsed.TotalSeconds -gt 0) { [int][Math]::Round($script:foProcessed / $script:foStopwatch.Elapsed.TotalSeconds) } else { $script:foProcessed }

        if ($CopyMatches -and $null -ne $script:foCopiedValues -and $script:foCopiedValues.Count -gt 0) {
            try {
                Set-Clipboard -Value ($script:foCopiedValues -join [Environment]::NewLine) -ErrorAction Stop
                Write-Host "  [CLIPBOARD] Copied $($script:foCopiedValues.Count) matched value(s) to clipboard." -ForegroundColor Green
            } catch {}
        }

        if ($CopyMarkdown -and $null -ne $script:foMarkdownRows -and $script:foMarkdownRows.Count -gt 0) {
            try {
                $mdLines = @(
                    "| # | Property | Matched Value | Type |",
                    "| :--- | :--- | :--- | :--- |"
                ) + $script:foMarkdownRows
                Set-Clipboard -Value ($mdLines -join [Environment]::NewLine) -ErrorAction Stop
                Write-Host "  [CLIPBOARD] Copied $($script:foMarkdownRows.Count) matched object(s) as Markdown table to clipboard." -ForegroundColor Green
            } catch {}
        }

        if ($CopyCsv -and $null -ne $script:foCsvRows -and $script:foCsvRows.Count -gt 0) {
            try {
                $csvLines = @('Index,Property,MatchedValue,Type') + $script:foCsvRows
                Set-Clipboard -Value ($csvLines -join [Environment]::NewLine) -ErrorAction Stop
                Write-Host "  [CLIPBOARD] Copied $($script:foCsvRows.Count) matched object(s) as CSV to clipboard." -ForegroundColor Green
            } catch {}
        }

        if ($CopyTsv -and $null -ne $script:foTsvRows -and $script:foTsvRows.Count -gt 0) {
            try {
                $tsvLines = @("Index`tProperty`tMatchedValue`tType") + $script:foTsvRows
                Set-Clipboard -Value ($tsvLines -join "`r`n") -ErrorAction Stop
                Write-Host "  [CLIPBOARD] Copied $($script:foTsvRows.Count) matched object(s) as TSV (Excel/Sheets ready) to clipboard." -ForegroundColor Green
            } catch {}
        }

        if ($CopyJson -and $null -ne $script:foJsonItems -and $script:foJsonItems.Count -gt 0) {
            try {
                $jsonText = $script:foJsonItems | ConvertTo-Json -Depth 4
                Set-Clipboard -Value $jsonText -ErrorAction Stop
                Write-Host "  [CLIPBOARD] Copied $($script:foJsonItems.Count) matched object(s) as JSON to clipboard." -ForegroundColor Green
            } catch {}
        }

        if ($CopyTypeSummary -and $null -ne $script:foTypeCounts -and $script:foTypeCounts.Count -gt 0) {
            try {
                $typeLines = @(
                    "### FindObject Matched .NET Type Breakdown ($script:foEmitted Matched / $script:foProcessed Scanned)",
                    "",
                    "| # | .NET Type | Matched Count | Share % |",
                    "| :- | :--- | :---: | :---: |"
                )
                $tIdx = 0
                foreach ($kv in ($script:foTypeCounts.GetEnumerator() | Sort-Object Value -Descending)) {
                    $tIdx++
                    $sharePct = if ($script:foEmitted -gt 0) { [Math]::Round(($kv.Value * 100.0) / $script:foEmitted, 1) } else { 0 }
                    $typeLines += "| $tIdx | ``$($kv.Key)`` | $($kv.Value) | ${sharePct}% |"
                }
                Set-Clipboard -Value ($typeLines -join "`r`n") -ErrorAction Stop
                Write-Host "  [CLIPBOARD] Copied $($script:foTypeCounts.Count) .NET type breakdown row(s) as Markdown table to clipboard." -ForegroundColor Green
            } catch {}
        }

        if ($CopyTypeTsv -and $null -ne $script:foTypeCounts -and $script:foTypeCounts.Count -gt 0) {
            try {
                $typeTsvLines = @("Index`tType`tMatchedCount`tSharePercent")
                $tIdx = 0
                foreach ($kv in ($script:foTypeCounts.GetEnumerator() | Sort-Object Value -Descending)) {
                    $tIdx++
                    $sharePct = if ($script:foEmitted -gt 0) { [Math]::Round(($kv.Value * 100.0) / $script:foEmitted, 1) } else { 0 }
                    $typeTsvLines += "$tIdx`t$($kv.Key)`t$($kv.Value)`t${sharePct}%"
                }
                Set-Clipboard -Value ($typeTsvLines -join "`r`n") -ErrorAction Stop
                Write-Host "  [CLIPBOARD] Copied $($script:foTypeCounts.Count) .NET type breakdown row(s) as TSV (Excel/Sheets ready) to clipboard." -ForegroundColor Green
            } catch {}
        }

        if ($CopyTypeJson -and $null -ne $script:foTypeCounts -and $script:foTypeCounts.Count -gt 0) {
            try {
                $typeItems = @()
                $tIdx = 0
                foreach ($kv in ($script:foTypeCounts.GetEnumerator() | Sort-Object Value -Descending)) {
                    $tIdx++
                    $sharePct = if ($script:foEmitted -gt 0) { [Math]::Round(($kv.Value * 100.0) / $script:foEmitted, 1) } else { 0 }
                    $typeItems += [PSCustomObject]@{
                        Index        = $tIdx
                        Type         = $kv.Key
                        MatchedCount = $kv.Value
                        SharePercent = $sharePct
                    }
                }
                $typePayload = [PSCustomObject]@{
                    GeneratedAt = (Get-Date).ToString('o')
                    Matched     = $script:foEmitted
                    Scanned     = $script:foProcessed
                    TypeCount   = $script:foTypeCounts.Count
                    Types       = $typeItems
                }
                Set-Clipboard -Value ($typePayload | ConvertTo-Json -Depth 5) -ErrorAction Stop
                Write-Host "  [CLIPBOARD] Copied $($script:foTypeCounts.Count) .NET type breakdown row(s) as JSON to clipboard." -ForegroundColor Green
            } catch {}
        }

        if ($CopySummary) {
            try {
                $hitPctReport = if ($script:foProcessed -gt 0) { [int][Math]::Round(($script:foEmitted / $script:foProcessed) * 100) } else { 0 }
                $propLabelReport = if ($AsString) { 'ToString()' } else { $Property }
                $topTypesReport = if ($null -ne $script:foTypeCounts -and $script:foTypeCounts.Count -gt 0) {
                    @($script:foTypeCounts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 4 | ForEach-Object { "$($_.Key) ($($_.Value))" }) -join ', '
                } else { 'N/A' }
                $samplesReport = if ($null -ne $script:foSampleValues -and $script:foSampleValues.Count -gt 0) {
                    ($script:foSampleValues -join ', ') -replace '\|', '\|'
                } else { 'None' }
                $reportLines = @(
                    "### FindObject Match Telemetry Report",
                    "",
                    "| Metric | Value |",
                    "| :--- | :--- |",
                    "| **Matched / Scanned** | **$script:foEmitted / $script:foProcessed** ($hitPctReport%) |",
                    "| **Mode / Property** | ``$Mode`` / ``$propLabelReport`` |",
                    "| **Clauses / CaseSensitive** | $clauseCount / $CaseSensitive |",
                    "| **Invert / Unique** | $Invert / $Unique (-$script:foDuplicatesFiltered dupes) |",
                    "| **Elapsed / Throughput** | ${elapsedMs}ms ($ratePerSec objs/s) |",
                    "| **Top .NET Types** | $topTypesReport |",
                    "| **Sample Matches** | $samplesReport |"
                )
                Set-Clipboard -Value ($reportLines -join "`r`n") -ErrorAction Stop
                Write-Host "  [CLIPBOARD] Copied FindObject match telemetry summary report (Markdown) to clipboard." -ForegroundColor Green
            } catch {}
        }

        if ($CopySummaryJson) {
            try {
                $hitPctJson = if ($script:foProcessed -gt 0) { [Math]::Round(($script:foEmitted * 100.0) / $script:foProcessed, 1) } else { 0 }
                $propLabelJson = if ($AsString) { 'ToString()' } else { $Property }
                $typeArr = @()
                if ($null -ne $script:foTypeCounts) {
                    foreach ($kv in ($script:foTypeCounts.GetEnumerator() | Sort-Object Value -Descending)) {
                        $typeArr += [PSCustomObject]@{ Type = $kv.Key; Count = $kv.Value }
                    }
                }
                $summaryObj = [PSCustomObject]@{
                    GeneratedAt        = (Get-Date).ToString('o')
                    Matched            = $script:foEmitted
                    Scanned            = $script:foProcessed
                    HitRatePercent     = $hitPctJson
                    Mode               = [string]$Mode
                    Property           = [string]$propLabelJson
                    Clauses            = $clauseCount
                    CaseSensitive      = [bool]$CaseSensitive
                    Invert             = [bool]$Invert
                    Unique             = [bool]$Unique
                    DuplicatesFiltered = $script:foDuplicatesFiltered
                    ElapsedMs          = $elapsedMs
                    ThroughputPerSec   = $ratePerSec
                    TypeBreakdown      = $typeArr
                    SampleMatches      = if ($null -ne $script:foSampleValues) { @($script:foSampleValues) } else { @() }
                }
                Set-Clipboard -Value ($summaryObj | ConvertTo-Json -Depth 5) -ErrorAction Stop
                Write-Host "  [CLIPBOARD] Copied FindObject match telemetry summary report (JSON) to clipboard." -ForegroundColor Green
            } catch {}
        }

        if ($CopySummaryTsv) {
            try {
                $hitPctTsv = if ($script:foProcessed -gt 0) { [Math]::Round(($script:foEmitted * 100.0) / $script:foProcessed, 1) } else { 0 }
                $propLabelTsv = if ($AsString) { 'ToString()' } else { $Property }
                $topTypesTsv = if ($null -ne $script:foTypeCounts -and $script:foTypeCounts.Count -gt 0) {
                    @($script:foTypeCounts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 4 | ForEach-Object { "$($_.Key) ($($_.Value))" }) -join ', '
                } else { 'N/A' }
                $samplesTsv = if ($null -ne $script:foSampleValues -and $script:foSampleValues.Count -gt 0) {
                    (($script:foSampleValues -join ', ') -replace "[\t\r\n]+", ' ').Trim()
                } else { 'None' }
                $tsvSumLines = @(
                    "Metric`tValue",
                    "Matched / Scanned`t$script:foEmitted / $script:foProcessed (${hitPctTsv}%)",
                    "Mode / Property`t$Mode / $propLabelTsv",
                    "Clauses / CaseSensitive`t$clauseCount / $CaseSensitive",
                    "Invert / Unique`t$Invert / $Unique (-$script:foDuplicatesFiltered dupes)",
                    "Elapsed / Throughput`t${elapsedMs}ms ($ratePerSec objs/s)",
                    "Top .NET Types`t$topTypesTsv",
                    "Sample Matches`t$samplesTsv"
                )
                Set-Clipboard -Value ($tsvSumLines -join "`r`n") -ErrorAction Stop
                Write-Host "  [CLIPBOARD] Copied FindObject match telemetry summary report (TSV) to clipboard." -ForegroundColor Green
            } catch {}
        }

        if ($CopySummaryCsv) {
            try {
                $hitPctCsv = if ($script:foProcessed -gt 0) { [Math]::Round(($script:foEmitted * 100.0) / $script:foProcessed, 1) } else { 0 }
                $propLabelCsv = if ($AsString) { 'ToString()' } else { $Property }
                $topTypesCsv = if ($null -ne $script:foTypeCounts -and $script:foTypeCounts.Count -gt 0) {
                    @($script:foTypeCounts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 4 | ForEach-Object { "$($_.Key) ($($_.Value))" }) -join ', '
                } else { 'N/A' }
                $samplesCsv = if ($null -ne $script:foSampleValues -and $script:foSampleValues.Count -gt 0) {
                    (($script:foSampleValues -join ', ') -replace '\r?\n', ' ').Replace('"', '""').Trim()
                } else { 'None' }
                $safePropCsv = ([string]$propLabelCsv).Replace('"', '""')
                $safeTypesCsv = ([string]$topTypesCsv).Replace('"', '""')
                $csvSumLines = @(
                    "Metric,Value",
                    "`"Matched / Scanned`",`"$script:foEmitted / $script:foProcessed (${hitPctCsv}%)`"",
                    "`"Mode / Property`",`"$Mode / $safePropCsv`"",
                    "`"Clauses / CaseSensitive`",`"$clauseCount / $CaseSensitive`"",
                    "`"Invert / Unique`",`"$Invert / $Unique (-$script:foDuplicatesFiltered dupes)`"",
                    "`"Elapsed / Throughput`",`"${elapsedMs}ms ($ratePerSec objs/s)`"",
                    "`"Top .NET Types`",`"$safeTypesCsv`"",
                    "`"Sample Matches`",`"$samplesCsv`""
                )
                Set-Clipboard -Value ($csvSumLines -join "`r`n") -ErrorAction Stop
                Write-Host "  [CLIPBOARD] Copied FindObject match telemetry summary report (CSV) to clipboard." -ForegroundColor Green
            } catch {}
        }

        if ($Summary) {
            $hitPct = if ($script:foProcessed -gt 0) { [int][Math]::Round(($script:foEmitted / $script:foProcessed) * 100) } else { 0 }
            $filled = [Math]::Max(0, [Math]::Min(10, [int][Math]::Round($hitPct / 10)))
            $bar = ('#' * $filled) + ('-' * (10 - $filled))
            $barColor = if ($script:foEmitted -gt 0) { 'Green' } else { 'Yellow' }
            $propLabel = if ($AsString) { 'ToString()' } else { $Property }
            $invBadge = if ($Invert) { ' [INVERTED]' } else { '' }
            $uniqBadge = if ($Unique) { " [UNIQUE: -$script:foDuplicatesFiltered dupes]" } else { '' }
            $mdBadge = if ($CopyMarkdown) { ' [MD COPIED]' } else { '' }
            $csvBadge = if ($CopyCsv) { ' [CSV COPIED]' } else { '' }
            $tsvBadge = if ($CopyTsv) { ' [TSV COPIED]' } else { '' }
            $jsonBadge = if ($CopyJson) { ' [JSON COPIED]' } else { '' }
            $typesBadge = if ($CopyTypeSummary) { ' [TYPES COPIED]' } else { '' }
            $typesTsvBadge = if ($CopyTypeTsv) { ' [TYPES TSV COPIED]' } else { '' }
            $typesJsonBadge = if ($CopyTypeJson) { ' [TYPES JSON COPIED]' } else { '' }
            $sumCopyBadge = if ($CopySummary) { ' [SUMMARY COPIED]' } else { '' }
            $sumJsonBadge = if ($CopySummaryJson) { ' [SUMMARY JSON COPIED]' } else { '' }
            $sumTsvBadge = if ($CopySummaryTsv) { ' [SUMMARY TSV COPIED]' } else { '' }
            $sumCsvBadge = if ($CopySummaryCsv) { ' [SUMMARY CSV COPIED]' } else { '' }
            Write-Host "`n  +----------------------------------------------------------------------+" -ForegroundColor DarkCyan
            Write-Host "  | FindObject Match Telemetry$invBadge$uniqBadge$mdBadge$csvBadge$tsvBadge$jsonBadge$typesBadge$typesTsvBadge$typesJsonBadge$sumCopyBadge$sumJsonBadge$sumTsvBadge$sumCsvBadge   [$bar] $script:foEmitted / $script:foProcessed matched ($hitPct%)" -ForegroundColor $barColor
            Write-Host "  | Mode: $Mode | Property: $propLabel | Clauses: $clauseCount | ${elapsedMs}ms ($ratePerSec objs/s)" -ForegroundColor Cyan
            if ($null -ne $script:foTypeCounts -and $script:foTypeCounts.Count -gt 0) {
                $topTypes = @($script:foTypeCounts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 4 | ForEach-Object { "$($_.Key) ($($_.Value))" }) -join ', '
                Write-Host "  | Types : $topTypes" -ForegroundColor DarkCyan
            }
            if ($null -ne $script:foSampleValues -and $script:foSampleValues.Count -gt 0) {
                $sampleStr = ($script:foSampleValues -join ', ')
                if ($sampleStr.Length -gt 58) { $sampleStr = $sampleStr.Substring(0, 55) + '...' }
                Write-Host "  | Sample: $sampleStr" -ForegroundColor Gray
            }
            Write-Host "  +----------------------------------------------------------------------+" -ForegroundColor DarkCyan
        }

        if ($Quiet) {
            Write-Output ($script:foMatchCount -gt 0)
            return
        }
        if ($Count) {
            Write-Output ($script:foMatchCount - $script:foSkipped)
            return
        }
        Write-Verbose "FindObject: processed=$script:foProcessed matched=$script:foMatchCount emitted=$script:foEmitted elapsed=${elapsedMs}ms"
    }

}

# Aliases
New-Alias -Name fob -Value Find-ObjectByName -Force

# Export
Export-ModuleMember -Function @(
    'Find-ObjectByName',
    'Get-FindObjectConfig',
    'Set-FindObjectConfig'
) -Alias @('fob')

