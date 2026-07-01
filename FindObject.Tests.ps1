$modulePath = Join-Path $PSScriptRoot "FindObject.psm1"
Import-Module $modulePath -Force

Describe "Find-ObjectByName" {

    Context "Backward-compatible logic" {
        It "should match a single keyword" {
            $obj = [PSCustomObject]@{ Name = "testObject" }
            $res = $obj | Find-ObjectByName -SearchTerms "test"
            $res | Should -Be $obj
        }

        It "should return objects matching any keyword by default (implicit OR)" {
            $obj1 = [PSCustomObject]@{ Name = "apple" }
            $obj2 = [PSCustomObject]@{ Name = "banana" }
            $obj3 = [PSCustomObject]@{ Name = "cherry" }
            $res = @($obj1, $obj2, $obj3) | Find-ObjectByName -SearchTerms "apple", "cherry"
            $res.Count | Should -Be 2
            $res | Should -Contain $obj1
            $res | Should -Contain $obj3
        }

        It "should require all keywords with explicit 'and'" {
            $obj1 = [PSCustomObject]@{ Name = "apple pie" }
            $obj2 = [PSCustomObject]@{ Name = "apple tart" }
            $obj3 = [PSCustomObject]@{ Name = "cherry pie" }
            $res = @($obj1, $obj2, $obj3) | Find-ObjectByName -SearchTerms "apple", "and", "pie"
            $res.Count | Should -Be 1
            $res | Should -Contain $obj1
        }

        It "should throw when only an operator is given with no keyword" {
            { Get-Process | Find-ObjectByName -SearchTerms "or" } | Should -Throw "No valid search keywords provided in '-SearchTerms' after parsing operators. Please provide at least one keyword."
        }

        It "should handle null pipeline input gracefully" {
            $res = $null | Find-ObjectByName -SearchTerms "test"
            $null -eq $res | Should -Be $true
        }

        It "should skip objects that are missing the target property" {
            $obj = [PSCustomObject]@{ Value = "testObject" }
            $res = $obj | Find-ObjectByName -SearchTerms "test"
            $null -eq $res | Should -Be $true
        }
    }

    Context "NOT logic (previously documented but never implemented)" {
        It "should exclude objects matching a NOT keyword" {
            $obj1 = [PSCustomObject]@{ Name = "chrome.exe" }
            $obj2 = [PSCustomObject]@{ Name = "chromehelper.exe" }
            $res = @($obj1, $obj2) | Find-ObjectByName -SearchTerms "chrome", "not", "helper"
            $res.Count | Should -Be 1
            $res | Should -Contain $obj1
        }

        It "should parse a natural-language string mixing OR and NOT" {
            $obj1 = [PSCustomObject]@{ Name = "chrome.exe" }
            $obj2 = [PSCustomObject]@{ Name = "firefox.exe" }
            $obj3 = [PSCustomObject]@{ Name = "chromehelper.exe" }
            $res = @($obj1, $obj2, $obj3) | Find-ObjectByName -SearchTerms "chrome OR firefox NOT helper"
            $res.Count | Should -Be 2
            $res | Should -Contain $obj1
            $res | Should -Contain $obj2
        }
    }

    Context "Matching modes" {
        It "should only match a leading prefix in StartsWith mode" {
            $obj1 = [PSCustomObject]@{ Name = "chrome.exe" }
            $obj2 = [PSCustomObject]@{ Name = "old-chrome.exe" }
            $res = @($obj1, $obj2) | Find-ObjectByName -SearchTerms "chrome" -Mode StartsWith
            $res.Count | Should -Be 1
            $res | Should -Contain $obj1
        }

        It "should match a non-contiguous subsequence in Fuzzy mode" {
            $obj = [PSCustomObject]@{ Name = "FindObject.psm1" }
            $res = $obj | Find-ObjectByName -SearchTerms "fndobj" -Mode Fuzzy
            $res | Should -Be $obj
        }

        It "should reject out-of-order characters in Fuzzy mode" {
            $obj = [PSCustomObject]@{ Name = "chrome.exe" }
            $res = $obj | Find-ObjectByName -SearchTerms "ehcrom" -Mode Fuzzy
            $null -eq $res | Should -Be $true
        }
    }

    Context "Targeting other properties or plain strings" {
        It "should match against a custom -Property instead of Name" {
            $obj1 = [PSCustomObject]@{ Name = "n/a"; ProcessName = "svchost" }
            $obj2 = [PSCustomObject]@{ Name = "n/a"; ProcessName = "explorer" }
            $res = @($obj1, $obj2) | Find-ObjectByName -SearchTerms "svchost" -Property ProcessName
            $res.Count | Should -Be 1
            $res | Should -Contain $obj1
        }

        It "should match plain strings via -AsString" {
            $res = "apple pie", "banana bread" | Find-ObjectByName -SearchTerms "pie" -AsString
            $res | Should -Be "apple pie"
        }
    }

    Context "Case sensitivity" {
        It "should only match exact case when -CaseSensitive is set" {
            $obj1 = [PSCustomObject]@{ Name = "Chrome.exe" }
            $obj2 = [PSCustomObject]@{ Name = "chrome.exe" }
            $res = @($obj1, $obj2) | Find-ObjectByName -SearchTerms "chrome" -CaseSensitive
            $res.Count | Should -Be 1
            $res | Should -Contain $obj2
        }
    }

    Context "Configuration" {
        AfterEach {
            Set-FindObjectConfig -Mode Contains | Out-Null
        }

        It "should use the default Mode set via Set-FindObjectConfig when -Mode isn't specified" {
            Set-FindObjectConfig -Mode Fuzzy | Out-Null
            (Get-FindObjectConfig).Mode | Should -Be 'Fuzzy'

            $obj = [PSCustomObject]@{ Name = "chrome.exe" }
            $res = $obj | Find-ObjectByName -SearchTerms "crome"
            $res | Should -Be $obj
        }
    }
}
