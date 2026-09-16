#Requires -Modules Pester

$modulePath = Join-Path $PSScriptRoot "FindObject.psm1"
Import-Module $modulePath -Force

Describe "Find-ObjectByName" {

    # ─── Basic matching ───────────────────────────────────────────────────────────

    Context "Basic Contains matching (default mode)" {
        It "matches a single keyword as substring" {
            $obj = [PSCustomObject]@{ Name = "testObject" }
            $obj | Find-ObjectByName "test" | Should -Be $obj
        }

        It "is case-insensitive by default" {
            $obj = [PSCustomObject]@{ Name = "TestObject" }
            $obj | Find-ObjectByName "testobject" | Should -Be $obj
        }

        It "does not match when keyword is absent" {
            $obj = [PSCustomObject]@{ Name = "hello" }
            $obj | Find-ObjectByName "xyz" | Should -BeNullOrEmpty
        }

        It "handles empty-name objects gracefully" {
            $obj = [PSCustomObject]@{ Name = "" }
            $obj | Find-ObjectByName "test" | Should -BeNullOrEmpty
        }
    }

    # ─── Logical operators ────────────────────────────────────────────────────────

    Context "Logical operators" {
        BeforeAll {
            $script:items = @(
                [PSCustomObject]@{ Name = "apple pie" }
                [PSCustomObject]@{ Name = "apple tart" }
                [PSCustomObject]@{ Name = "cherry pie" }
                [PSCustomObject]@{ Name = "banana bread" }
            )
        }

        It "implicit OR: bare keywords match any" {
            $res = $script:items | Find-ObjectByName "apple", "cherry"
            $res.Count | Should -Be 3
        }

        It "explicit OR via array syntax" {
            $res = $script:items | Find-ObjectByName "apple", "or", "banana"
            $res.Count | Should -Be 3
        }

        It "AND requires all keywords present" {
            $res = $script:items | Find-ObjectByName "apple", "and", "pie"
            $res.Count | Should -Be 1
            $res.Name | Should -Be "apple pie"
        }

        It "NOT excludes matching objects" {
            $res = $script:items | Find-ObjectByName "pie", "not", "cherry"
            $res.Count | Should -Be 1
            $res.Name | Should -Be "apple pie"
        }

        It "natural-language string: 'apple AND pie NOT tart'" {
            $res = $script:items | Find-ObjectByName "apple AND pie NOT tart"
            $res.Count | Should -Be 1
            $res.Name | Should -Be "apple pie"
        }

        It "natural-language string: 'apple OR cherry NOT tart'" {
            $res = $script:items | Find-ObjectByName "apple OR cherry NOT tart"
            $res.Count | Should -Be 2
        }

        It "throws on operator-only input" {
            { [PSCustomObject]@{ Name = "x" } | Find-ObjectByName "or" } | Should -Throw "*No valid search keywords*"
        }
    }

    # ─── Milestone 1: Core Lexer, Parser & Boolean AST Engine ─────────────────────

    Context "Milestone 1: Quoted Phrases (F1)" {
        BeforeAll {
            $script:appItems = @(
                [PSCustomObject]@{ Name = "Google Chrome Setup" }
                [PSCustomObject]@{ Name = "Google Setup" }
                [PSCustomObject]@{ Name = "Chrome Standalone Setup" }
                [PSCustomObject]@{ Name = "Tom and Jerry" }
                [PSCustomObject]@{ Name = 'He said "Hello" to me' }
                [PSCustomObject]@{ Name = "Microsoft Edge" }
            )
        }

        It "preserves double-quoted multi-word phrase with AND operator" {
            $res = $script:appItems | Find-ObjectByName '"Google Chrome" AND Setup'
            $res.Count | Should -Be 1
            $res.Name | Should -Be "Google Chrome Setup"
        }

        It "preserves single-quoted multi-word phrase with AND operator" {
            $res = $script:appItems | Find-ObjectByName "'Google Chrome' AND Setup"
            $res.Count | Should -Be 1
            $res.Name | Should -Be "Google Chrome Setup"
        }

        It "does not match when only part of a quoted phrase is present" {
            $res = $script:appItems | Find-ObjectByName '"Google Chrome"'
            $res.Count | Should -Be 1
            $res.Name | Should -Be "Google Chrome Setup"
            ($res | Where-Object { $_.Name -eq "Google Setup" }) | Should -BeNullOrEmpty
        }

        It "treats boolean keyword 'and' inside quotes as literal string text" {
            $res = $script:appItems | Find-ObjectByName '"Tom and Jerry"'
            $res.Count | Should -Be 1
            $res.Name | Should -Be "Tom and Jerry"
        }

        It "matches quoted phrase exactly in Exact mode without quote delimiters" {
            $target = [PSCustomObject]@{ Name = "Google Chrome" }
            $other = [PSCustomObject]@{ Name = "Google Chrome Setup" }
            $res = @($target, $other) | Find-ObjectByName '"Google Chrome"' -Mode Exact
            $res.Count | Should -Be 1
            $res.Name | Should -Be "Google Chrome"
        }

        It "handles escaped quotes within quoted strings" {
            $res = $script:appItems | Find-ObjectByName '"He said ""Hello"" to me"'
            $res.Count | Should -Be 1
            $res.Name | Should -Be 'He said "Hello" to me'
        }
    }

    Context "Milestone 1: Boolean Operators and Aliases (F2)" {
        BeforeAll {
            $script:fruits = @(
                [PSCustomObject]@{ Name = "apple pie" }
                [PSCustomObject]@{ Name = "apple tart" }
                [PSCustomObject]@{ Name = "cherry pie" }
                [PSCustomObject]@{ Name = "banana bread" }
            )
        }

        It "supports case-insensitive operator keywords: AND, and, aNd" {
            $res1 = $script:fruits | Find-ObjectByName "apple AND pie"
            $res2 = $script:fruits | Find-ObjectByName "apple and pie"
            $res3 = $script:fruits | Find-ObjectByName "apple aNd pie"
            $res1.Count | Should -Be 1
            $res2.Count | Should -Be 1
            $res3.Count | Should -Be 1
        }

        It "supports case-insensitive operator keywords: OR, or, Or" {
            $res1 = $script:fruits | Find-ObjectByName "apple OR cherry"
            $res2 = $script:fruits | Find-ObjectByName "apple or cherry"
            $res1.Count | Should -Be 3
            $res2.Count | Should -Be 3
        }

        It "supports operator symbol && for AND" {
            $res = $script:fruits | Find-ObjectByName "apple && pie"
            $res.Count | Should -Be 1
            $res.Name | Should -Be "apple pie"
        }

        It "supports operator symbol || for OR" {
            $res = $script:fruits | Find-ObjectByName "banana || cherry"
            $res.Count | Should -Be 2
        }

        It "supports operator symbol ! for NOT" {
            $res = $script:fruits | Find-ObjectByName "pie && !cherry"
            $res.Count | Should -Be 1
            $res.Name | Should -Be "apple pie"
        }

        It "supports PowerShell-style operator -and, -or, -not" {
            $res = $script:fruits | Find-ObjectByName "apple -and pie -not tart"
            $res.Count | Should -Be 1
            $res.Name | Should -Be "apple pie"
        }
    }

    Context "Milestone 1: Operator Precedence NOT > AND > OR (F3)" {
        BeforeAll {
            $script:triples = @(
                [PSCustomObject]@{ Name = "Apple" }
                [PSCustomObject]@{ Name = "Banana" }
                [PSCustomObject]@{ Name = "Cherry" }
                [PSCustomObject]@{ Name = "Banana Cherry" }
                [PSCustomObject]@{ Name = "Apple Banana" }
                [PSCustomObject]@{ Name = "Apple Cherry" }
                [PSCustomObject]@{ Name = "Apple Banana Cherry" }
                [PSCustomObject]@{ Name = "Date" }
            )
        }

        It "evaluates 'Apple OR Banana AND Cherry' as 'Apple OR (Banana AND Cherry)'" {
            $res = $script:triples | Find-ObjectByName "Apple OR Banana AND Cherry"
            $names = @($res | ForEach-Object { $_.Name })
            $names | Should -Contain "Apple"
            $names | Should -Contain "Banana Cherry"
            $names | Should -Not -Contain "Banana"
            $names | Should -Not -Contain "Cherry"
            $names | Should -Not -Contain "Date"
            $res.Count | Should -Be 5
        }

        It "evaluates 'Apple AND Banana OR Cherry' as '(Apple AND Banana) OR Cherry'" {
            $res = $script:triples | Find-ObjectByName "Apple AND Banana OR Cherry"
            $names = @($res | ForEach-Object { $_.Name })
            $names | Should -Contain "Apple Banana"
            $names | Should -Contain "Cherry"
            $names | Should -Not -Contain "Apple"
            $names | Should -Not -Contain "Banana"
            $names | Should -Not -Contain "Date"
            $res.Count | Should -Be 5
        }
    }

    Context "Milestone 1: Parentheses Grouping (F4)" {
        BeforeAll {
            $script:triples = @(
                [PSCustomObject]@{ Name = "Apple" }
                [PSCustomObject]@{ Name = "Banana" }
                [PSCustomObject]@{ Name = "Cherry" }
                [PSCustomObject]@{ Name = "Banana Cherry" }
                [PSCustomObject]@{ Name = "Apple Cherry" }
                [PSCustomObject]@{ Name = "Apple Banana Cherry" }
                [PSCustomObject]@{ Name = "Date" }
            )
        }

        It "evaluates '(Apple OR Banana) AND Cherry' overriding standard precedence" {
            $res = $script:triples | Find-ObjectByName "(Apple OR Banana) AND Cherry"
            $names = @($res | ForEach-Object { $_.Name })
            $names | Should -Contain "Apple Cherry"
            $names | Should -Contain "Banana Cherry"
            $names | Should -Contain "Apple Banana Cherry"
            $names | Should -Not -Contain "Apple"
            $names | Should -Not -Contain "Banana"
            $names | Should -Not -Contain "Cherry"
            $names | Should -Not -Contain "Date"
            $res.Count | Should -Be 3
        }

        It "evaluates nested parentheses '((Apple OR Banana) AND (Cherry OR Date))'" {
            $items = @(
                [PSCustomObject]@{ Name = "Apple Cherry" }
                [PSCustomObject]@{ Name = "Banana Date" }
                [PSCustomObject]@{ Name = "Apple Elderberry" }
                [PSCustomObject]@{ Name = "Cherry Date" }
            )
            $res = $items | Find-ObjectByName "((Apple OR Banana) AND (Cherry OR Date))"
            $names = @($res | ForEach-Object { $_.Name })
            $names | Should -Contain "Apple Cherry"
            $names | Should -Contain "Banana Date"
            $names | Should -Not -Contain "Apple Elderberry"
            $names | Should -Not -Contain "Cherry Date"
            $res.Count | Should -Be 2
        }

        It "throws a descriptive error on unclosed parenthesis" {
            { [PSCustomObject]@{ Name = "test" } | Find-ObjectByName "(Apple AND Banana" } | Should -Throw "*Unclosed parenthesis*"
        }
    }

    Context "Milestone 1: Unary NOT Evaluation (F5)" {
        BeforeAll {
            $script:procItems = @(
                [PSCustomObject]@{ Name = "helper.exe" }
                [PSCustomObject]@{ Name = "chrome.exe" }
                [PSCustomObject]@{ Name = "svchost.exe" }
                [PSCustomObject]@{ Name = "helper-service.exe" }
            )
        }

        It "evaluates leading unary 'NOT helper' correctly excluding matching items" {
            $res = $script:procItems | Find-ObjectByName "NOT helper"
            $names = @($res | ForEach-Object { $_.Name })
            $names | Should -Contain "chrome.exe"
            $names | Should -Contain "svchost.exe"
            $names | Should -Not -Contain "helper.exe"
            $names | Should -Not -Contain "helper-service.exe"
            $res.Count | Should -Be 2
        }

        It "evaluates leading unary '!helper' symbol alias" {
            $res = $script:procItems | Find-ObjectByName "!helper"
            $names = @($res | ForEach-Object { $_.Name })
            $names | Should -Contain "chrome.exe"
            $names | Should -Contain "svchost.exe"
            $names | Should -Not -Contain "helper.exe"
            $res.Count | Should -Be 2
        }

        It "evaluates leading unary '-not helper' PowerShell alias" {
            $res = $script:procItems | Find-ObjectByName "-not helper"
            $names = @($res | ForEach-Object { $_.Name })
            $names | Should -Contain "chrome.exe"
            $names | Should -Contain "svchost.exe"
            $names | Should -Not -Contain "helper.exe"
            $res.Count | Should -Be 2
        }

        It "evaluates binary 'apple OR NOT cherry' correctly" {
            $fruitItems = @(
                [PSCustomObject]@{ Name = "apple" }
                [PSCustomObject]@{ Name = "banana" }
                [PSCustomObject]@{ Name = "cherry pie" }
                [PSCustomObject]@{ Name = "apple cherry" }
            )
            $res = $fruitItems | Find-ObjectByName "apple OR NOT cherry"
            $names = @($res | ForEach-Object { $_.Name })
            $names | Should -Contain "apple"
            $names | Should -Contain "banana"
            $names | Should -Contain "apple cherry"
            $names | Should -Not -Contain "cherry pie"
            $res.Count | Should -Be 3
        }

        It "evaluates 'NOT (Banana OR Cherry)' with grouped exclusion" {
            $fruitItems = @(
                [PSCustomObject]@{ Name = "apple" }
                [PSCustomObject]@{ Name = "banana" }
                [PSCustomObject]@{ Name = "cherry" }
                [PSCustomObject]@{ Name = "date" }
            )
            $res = $fruitItems | Find-ObjectByName "NOT (Banana OR Cherry)"
            $names = @($res | ForEach-Object { $_.Name })
            $names | Should -Contain "apple"
            $names | Should -Contain "date"
            $names | Should -Not -Contain "banana"
            $names | Should -Not -Contain "cherry"
            $res.Count | Should -Be 2
        }
    }

    # ─── Matching modes ───────────────────────────────────────────────────────────

    Context "StartsWith mode" {
        It "matches only at the beginning" {
            $items = @(
                [PSCustomObject]@{ Name = "chrome.exe" }
                [PSCustomObject]@{ Name = "old-chrome.exe" }
            )
            $res = $items | Find-ObjectByName "chrome" -Mode StartsWith
            $res.Count | Should -Be 1
            $res.Name | Should -Be "chrome.exe"
        }
    }

    Context "Fuzzy mode" {
        It "matches non-contiguous subsequence" {
            $obj = [PSCustomObject]@{ Name = "FindObject.psm1" }
            $obj | Find-ObjectByName "fndobj" -Mode Fuzzy | Should -Be $obj
        }

        It "rejects out-of-order characters" {
            $obj = [PSCustomObject]@{ Name = "chrome.exe" }
            $obj | Find-ObjectByName "ehcrom" -Mode Fuzzy | Should -BeNullOrEmpty
        }

        It "matches single character pattern" {
            $obj = [PSCustomObject]@{ Name = "abc" }
            $obj | Find-ObjectByName "b" -Mode Fuzzy | Should -Be $obj
        }
    }

    Context "Exact mode" {
        It "matches only full string equality" {
            $items = @(
                [PSCustomObject]@{ Name = "chrome" }
                [PSCustomObject]@{ Name = "chrome.exe" }
            )
            $res = $items | Find-ObjectByName "chrome" -Mode Exact
            $res.Count | Should -Be 1
            $res.Name | Should -Be "chrome"
        }

        It "is case-insensitive by default" {
            $obj = [PSCustomObject]@{ Name = "Chrome" }
            $obj | Find-ObjectByName "chrome" -Mode Exact | Should -Be $obj
        }

        It "respects -CaseSensitive" {
            $obj = [PSCustomObject]@{ Name = "Chrome" }
            $obj | Find-ObjectByName "chrome" -Mode Exact -CaseSensitive | Should -BeNullOrEmpty
        }
    }

    Context "Regex mode" {
        It "supports .NET regex patterns" {
            $items = @(
                [PSCustomObject]@{ Name = "file001.log" }
                [PSCustomObject]@{ Name = "file002.txt" }
                [PSCustomObject]@{ Name = "readme.md" }
            )
            $res = $items | Find-ObjectByName 'file\d+\.log' -Mode Regex
            $res.Count | Should -Be 1
            $res.Name | Should -Be "file001.log"
        }

        It "is case-insensitive by default" {
            $obj = [PSCustomObject]@{ Name = "ERROR_LOG" }
            $obj | Find-ObjectByName "error" -Mode Regex | Should -Be $obj
        }
    }

    # ─── Property targeting ───────────────────────────────────────────────────────

    Context "Property targeting" {
        It "matches a custom -Property" {
            $items = @(
                [PSCustomObject]@{ Name = "n/a"; ProcessName = "svchost" }
                [PSCustomObject]@{ Name = "n/a"; ProcessName = "explorer" }
            )
            $res = $items | Find-ObjectByName "svchost" -Property ProcessName
            $res.Count | Should -Be 1
            $res.ProcessName | Should -Be "svchost"
        }

        It "-AsString matches the object's string form" {
            $res = "apple pie", "banana bread" | Find-ObjectByName "pie" -AsString
            $res | Should -Be "apple pie"
        }

        It "-Property * searches all string properties" {
            $items = @(
                [PSCustomObject]@{ Name = "alpha"; Description = "beta target" }
                [PSCustomObject]@{ Name = "gamma"; Description = "delta" }
            )
            $res = $items | Find-ObjectByName "target" -Property *
            $res.Count | Should -Be 1
            $res.Name | Should -Be "alpha"
        }

        It "skips objects missing the target property" {
            $obj = [PSCustomObject]@{ Value = "test" }
            $obj | Find-ObjectByName "test" | Should -BeNullOrEmpty
        }
    }

    # ─── Case sensitivity ─────────────────────────────────────────────────────────

    Context "Case sensitivity" {
        It "matches exact case with -CaseSensitive" {
            $items = @(
                [PSCustomObject]@{ Name = "Chrome.exe" }
                [PSCustomObject]@{ Name = "chrome.exe" }
            )
            $res = $items | Find-ObjectByName "chrome" -CaseSensitive
            $res.Count | Should -Be 1
            $res.Name | Should -Be "chrome.exe"
        }
    }

    # ─── Result limiting ──────────────────────────────────────────────────────────

    Context "Result limiting (-First, -Skip)" {
        BeforeAll {
            $script:manyItems = 1..100 | ForEach-Object { [PSCustomObject]@{ Name = "item$_" } }
        }

        It "-First N stops after N matches" {
            $res = $script:manyItems | Find-ObjectByName "item" -First 5
            $res.Count | Should -Be 5
        }

        It "-Skip N discards the first N matches" {
            $res = $script:manyItems | Find-ObjectByName "item" -Skip 95
            $res.Count | Should -Be 5
        }

        It "-First and -Skip combine for paging" {
            $res = $script:manyItems | Find-ObjectByName "item" -Skip 10 -First 5
            $res.Count | Should -Be 5
            $res[0].Name | Should -Be "item11"
        }
    }

    # ─── Count and Quiet ──────────────────────────────────────────────────────────

    Context "Count and Quiet switches" {
        BeforeAll {
            $script:items = @(
                [PSCustomObject]@{ Name = "apple" }
                [PSCustomObject]@{ Name = "banana" }
                [PSCustomObject]@{ Name = "apricot" }
            )
        }

        It "-Count returns the number of matches" {
            $res = $script:items | Find-ObjectByName "ap" -Count
            $res | Should -Be 2
            $res | Should -BeOfType [int]
        }

        It "-Quiet returns `$true when matches exist" {
            $res = $script:items | Find-ObjectByName "banana" -Quiet
            $res | Should -Be $true
        }

        It "-Quiet returns `$false when no matches" {
            $res = $script:items | Find-ObjectByName "xyz" -Quiet
            $res | Should -Be $false
        }
    }

    # ─── Null / edge cases ────────────────────────────────────────────────────────

    Context "Edge cases" {
        It "handles null pipeline input" {
            $null | Find-ObjectByName "test" | Should -BeNullOrEmpty
        }

        It "handles objects with null Name" {
            $obj = [PSCustomObject]@{ Name = $null }
            $obj | Find-ObjectByName "test" | Should -BeNullOrEmpty
        }

        It "handles whitespace-only Name" {
            $obj = [PSCustomObject]@{ Name = "   " }
            $obj | Find-ObjectByName "test" | Should -BeNullOrEmpty
        }
    }

    # ─── Configuration ────────────────────────────────────────────────────────────

    Context "Configuration" {
        AfterEach {
            Set-FindObjectConfig -Mode Contains | Out-Null
        }

        It "uses config default Mode when -Mode not specified" {
            Set-FindObjectConfig -Mode Fuzzy | Out-Null
            $obj = [PSCustomObject]@{ Name = "chrome.exe" }
            $obj | Find-ObjectByName "crome" | Should -Be $obj
        }

        It "Get-FindObjectConfig reflects changes" {
            Set-FindObjectConfig -Mode StartsWith | Out-Null
            (Get-FindObjectConfig).Mode | Should -Be 'StartsWith'
        }
    }

    # ─── Performance sanity check ─────────────────────────────────────────────────

    Context "Performance" {
        It "processes 50k objects in under 10 seconds (Contains mode)" {
            $data = 1..50000 | ForEach-Object { [PSCustomObject]@{ Name = "ProcessName_$_" } }
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $null = $data | Find-ObjectByName "ProcessName_25000"
            $sw.Stop()
            $sw.Elapsed.TotalSeconds | Should -BeLessThan 10
        }

        It "-First 1 terminates early on large input" {
            $data = 1..50000 | ForEach-Object { [PSCustomObject]@{ Name = "item_$_" } }
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $res = $data | Find-ObjectByName "item_1" -First 1
            $sw.Stop()
            $res.Count | Should -Be 1
            $sw.Elapsed.TotalSeconds | Should -BeLessThan 2
        }
    }
}

Describe "Microsoft Graph / Intune Integration" {
    BeforeAll {
        $intunePath = Join-Path $PSScriptRoot "FindObject.Intune.psd1"
        if (-not (Test-Path $intunePath)) {
            $intunePath = Join-Path $PSScriptRoot "FindObject.Intune.psm1"
        }
        Import-Module $intunePath -Force
    }

    Context "Module exports" {
        It "exports Connect-FindObjectGraph" {
            Get-Command Connect-FindObjectGraph -Module FindObject.Intune | Should -Not -BeNullOrEmpty
        }

        It "exports Disconnect-FindObjectGraph" {
            Get-Command Disconnect-FindObjectGraph -Module FindObject.Intune | Should -Not -BeNullOrEmpty
        }

        It "exports all Get-Intune* cmdlets" {
            $expected = @('Get-IntuneDevice', 'Get-IntuneApp', 'Get-IntuneCompliancePolicy',
                'Get-IntuneConfigProfile', 'Get-IntuneAutopilotDevice', 'Get-IntuneEnrollment')
            foreach ($cmd in $expected) {
                Get-Command $cmd -Module FindObject.Intune | Should -Not -BeNullOrEmpty
            }
        }

        It "exports the 'gid' alias for Get-IntuneDevice" {
            (Get-Alias gid -ErrorAction SilentlyContinue).Definition | Should -Be 'Get-IntuneDevice'
        }
    }

    Context "Auth guard" {
        BeforeAll {
            Disconnect-FindObjectGraph
        }

        It "Get-IntuneDevice throws when not connected" {
            { Get-IntuneDevice } | Should -Throw "*Connect-FindObjectGraph*"
        }

        It "Get-IntuneApp throws when not connected" {
            { Get-IntuneApp } | Should -Throw "*Connect-FindObjectGraph*"
        }

        It "Get-IntuneCompliancePolicy throws when not connected" {
            { Get-IntuneCompliancePolicy } | Should -Throw "*Connect-FindObjectGraph*"
        }
    }

    Context "Disconnect clears state" {
        It "Disconnect-FindObjectGraph runs without error" {
            { Disconnect-FindObjectGraph } | Should -Not -Throw
        }
    }
}
