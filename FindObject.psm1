function Find-ObjectByName {
    <#
    .SYNOPSIS
    Filters pipeline objects based on whether their 'Name' property contains specified keywords using AND or OR logic.

    .DESCRIPTION
    Accepts objects via the pipeline. Filters these objects based on keywords provided via the -SearchTerms parameter.
    Looks for the literal strings 'or' or 'and' within the search terms to determine the filtering logic.
    If neither 'or' nor 'and' is specified, defaults to OR logic if multiple keywords are given.
    Performs case-insensitive wildcard searches (*keyword*) on the 'Name' property of the input objects.

    .PARAMETER SearchTerms
    An array of strings containing the keywords and optionally 'or' or 'and' to specify the logic.
    You must explicitly use the '-SearchTerms' parameter name when providing multiple arguments (e.g., keywords and logic operators).

    .PARAMETER InputObject
    The object(s) passed from the pipeline. This function expects the object(s) to have a 'Name' property.

    .EXAMPLE
    Get-Command -Module MicrosoftTeams | Find-ObjectByName -SearchTerms get, or, policy
    # Finds commands from MicrosoftTeams module whose Name contains 'get' OR 'policy'.

    .EXAMPLE
    Get-Command -Module MicrosoftTeams | Find-ObjectByName -SearchTerms get, and, policy
    # Finds commands from MicrosoftTeams module whose Name contains 'get' AND 'policy'.

    .EXAMPLE
    Get-Service | Find-ObjectByName -SearchTerms spool, print
    # Finds services whose Name contains 'spool' OR 'print' (OR is default for multiple keywords without 'or'/'and').

    .EXAMPLE
    Get-Process | Find-ObjectByName -SearchTerms chrome
    # Finds processes whose Name contains 'chrome'. Single terms often don't require the parameter name.

    .EXAMPLE
    Get-Command -Module PKI | Find-ObjectByName -SearchTerms cert, and, request -Verbose
    # Finds commands in the PKI module containing both 'cert' and 'request', showing verbose output.

    .NOTES
    - You MUST use the '-SearchTerms' parameter name when providing more than one argument (keyword or operator).
    - The function looks for the literal words 'or' and 'and' as distinct arguments within the -SearchTerms array to set the logic.
    - It uses the first 'or' or 'and' found to determine the logic if both are somehow provided.
    - If only one keyword is provided, it finds objects whose name contains that keyword.
    - Expects input objects to have a .Name property. Objects without it will be skipped with a verbose message.
    - Comparison is case-insensitive. Wildcards (*) are automatically added around keywords.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)] # Position 0 allows single keyword without naming param
        [string[]]$SearchTerms,

        [Parameter(ValueFromPipeline = $true)]
        [psobject]$InputObject
    )

    begin {
        # --- Parse SearchTerms to find keywords and logic ---
        $keywords = @()
        $logic = 'OR' # Default logic
        $logicSet = $false

        Write-Verbose "Raw SearchTerms received: $($SearchTerms -join ', ')"

        foreach ($term in $SearchTerms) {
            if (-not $logicSet -and $term -ieq 'or') {
                $logic = 'OR'
                $logicSet = $true
                Write-Verbose 'Logic operator found: OR'
            } elseif (-not $logicSet -and $term -ieq 'and') {
                $logic = 'AND'
                $logicSet = $true
                Write-Verbose 'Logic operator found: AND'
            } else {
                # Add non-operator terms to keywords list
                if (-not [string]::IsNullOrWhiteSpace($term)) {
                    $keywords += $term
                    Write-Verbose "Keyword added: $term"
                } else {
                    Write-Verbose 'Skipping empty or whitespace term.'
                }
            }
        }

        # If only one keyword was provided, logic doesn't really matter for the check itself
        if ($keywords.Count -eq 1) {
            Write-Verbose "Single keyword found: '$($keywords[0])'. Applying single match logic."
        } elseif ($keywords.Count -gt 1 -and !$logicSet) {
            Write-Verbose "Multiple keywords ($($keywords.Count)) found without explicit 'or'/'and'. Defaulting to OR logic."
            $logic = 'OR' # Explicitly set default for multiple keywords
        } elseif ($keywords.Count -eq 0) {
            # Throw error if NO keywords are left after parsing operators
            throw "No valid search keywords provided in '-SearchTerms' after parsing operators. Please provide at least one keyword."
        }

        # Store parsed info for process block using script scope
        # Script scope is used here to make variables easily accessible in the 'process' block
        # without needing to pass them explicitly for each object.
        $script:FinderKeywords = $keywords
        $script:FinderLogic = $logic

        Write-Verbose "Finder initialized. Logic: $script:FinderLogic, Keywords: $($script:FinderKeywords -join ', ')"
    }

    process {
        # Process each object from the pipeline
        if ($null -eq $InputObject) {
            Write-Verbose 'Received null InputObject. Skipping.'
            return
        }

        # Check if the input object has a 'Name' property
        $nameProperty = $InputObject.PSObject.Properties['Name']
        if ($null -eq $nameProperty) {
            Write-Verbose "Input object type '$($InputObject.GetType().FullName)' does not have a 'Name' property. Skipping."
            return # Skip this object
        }

        $objectName = $nameProperty.Value
        if ($null -eq $objectName) {
            # Handle cases where the Name property exists but its value is null
            Write-Verbose 'Input object has a null Name property value. Skipping.'
            return
        }

        # Ensure it's a string before doing string operations
        $objectName = $objectName.ToString()
        if ([string]::IsNullOrWhiteSpace($objectName)) {
            Write-Verbose "Input object's Name property is empty or whitespace. Skipping."
            return # Skip this object
        }

        # --- Apply Filtering Logic ---
        $match = $false
        if ($script:FinderLogic -eq 'OR') {
            # OR Logic: Check if the name contains ANY of the keywords
            $match = $false # Assume no match initially for OR
            foreach ($keyword in $script:FinderKeywords) {
                if ($objectName -like "*$keyword*") {
                    $match = $true
                    Write-Verbose "OR match found for keyword '$keyword' in name '$objectName'"
                    break # Found one match, no need to check others for OR
                }
            }
        } else {
            # Logic is AND
            # AND Logic: Check if the name contains ALL of the keywords
            $match = $true # Assume it matches until proven otherwise for AND
            if ($script:FinderKeywords.Count -eq 0) {
                $match = $false # Cannot match AND with zero keywords
                Write-Verbose 'AND logic requires keywords, none found. No match.'
            } else {
                foreach ($keyword in $script:FinderKeywords) {
                    if ($objectName -notlike "*$keyword*") {
                        $match = $false
                        Write-Verbose "AND condition failed: keyword '$keyword' not found in name '$objectName'"
                        break # Found one keyword that doesn't match, no need for further checks for AND
                    } else {
                        Write-Verbose "AND condition met (so far): keyword '$keyword' found in name '$objectName'"
                    }
                }
            }
        }

        # --- Output if Match ---
        if ($match) {
            Write-Verbose "Object '$objectName' passed the filter. Outputting."
            Write-Output $InputObject
        } else {
            Write-Verbose "Object '$objectName' did not pass the filter."
        }
    }

    end {
        # Cleanup script-scoped variables (optional, but good practice)
        if (Test-Path Variable:Script:FinderKeywords) {
            Remove-Variable -Name FinderKeywords -Scope Script -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path Variable:Script:FinderLogic) {
            Remove-Variable -Name FinderLogic -Scope Script -Force -ErrorAction SilentlyContinue
        }
        Write-Verbose 'Find-ObjectByName finished processing pipeline input.'
    }
}

# Create aliases
New-Alias -Name fob -Value Find-ObjectByName

# Export the function and aliases
Export-ModuleMember -Function Find-ObjectByName -Alias fob

# Get-Command -Module MicrosoftTeams | Find-ObjectByName -SearchTerms get, or, policy
# Get-Command -Module MicrosoftTeams | Find-ObjectByName -SearchTerms get, and, policy
# Get-Command -Module MicrosoftTeams | Find-ObjectByName -SearchTerms user, sync # Default OR
# Get-Command -Module MicrosoftTeams | Find-ObjectByName -SearchTerms meeting # Single term
# Get-Service | Find-ObjectByName -SearchTerms spool, print, fax -Verbose
# Get-Process | Find-ObjectByName -SearchTerms powershell, and, core -Verbose