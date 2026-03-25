$code = Get-Content -Path .\FindObject.psm1 -Raw

$search1 = '(?s)\$FinderKeywords = \$keywords.*?(?=    process \{)'
$replace1 = '$FinderKeywords = $keywords.ToArray()
        $FinderWildcardKeywords = [string[]]::new($FinderKeywords.Count)
        for ($i = 0; $i -lt $FinderKeywords.Count; $i++) {
            $FinderWildcardKeywords[$i] = "*$($FinderKeywords[$i])*"
        }
        $FinderLogic = $logic

        Write-Verbose "Finder initialized. Logic: $FinderLogic, Keywords: $($FinderKeywords -join '', '')"
    }
'
$code = $code -replace $search1, $replace1

$code = $code -replace '\$objectName = \$objectName\.ToString\(\)', 'if ($objectName -isnot [string]) { $objectName = [string]$objectName }'

$searchBlock = '(?s)        # --- Apply Filtering Logic ---.*?(?=    end \{)'
$replaceBlock = '        # --- Apply Filtering Logic ---
        $count = $FinderWildcardKeywords.Length
        if ($FinderLogic -eq ''OR'') {
            for ($i = 0; $i -lt $count; $i++) {
                if ($objectName -like $FinderWildcardKeywords[$i]) {
                    Write-Verbose "OR match found for keyword ''$($FinderKeywords[$i])'' in name ''$objectName''"
                    Write-Verbose "Object ''$objectName'' passed the filter. Outputting."
                    Write-Output $InputObject
                    return
                }
            }
        } else {
            if ($count -eq 0) {
                Write-Verbose ''AND logic requires keywords, none found. No match.''
                Write-Verbose "Object ''$objectName'' did not pass the filter."
                return
            } else {
                for ($i = 0; $i -lt $count; $i++) {
                    if ($objectName -notlike $FinderWildcardKeywords[$i]) {
                        Write-Verbose "AND condition failed: keyword ''$($FinderKeywords[$i])'' not found in name ''$objectName''"
                        Write-Verbose "Object ''$objectName'' did not pass the filter."
                        return
                    } else {
                        Write-Verbose "AND condition met (so far): keyword ''$($FinderKeywords[$i])'' found in name ''$objectName''"
                    }
                }
                Write-Verbose "Object ''$objectName'' passed the filter. Outputting."
                Write-Output $InputObject
                return
            }
        }

        Write-Verbose "Object ''$objectName'' did not pass the filter."
    }

'
$code = $code -replace $searchBlock, $replaceBlock

Set-Content -Path .\FindObject_Optimized.psm1 -Value $code
