$modulePath = Join-Path $PSScriptRoot "FindObject.psm1"
Import-Module $modulePath -Force

Describe "Find-ObjectByName" {
    Context "Single Keyword Search" {
        It "should match a single keyword" {
            $obj = [PSCustomObject]@{ Name = "testObject" }
            $res = $obj | Find-ObjectByName -SearchTerms "test"
            $res | Should -Be $obj
        }
    }

    Context "Default Logic (OR)" {
        It "should return objects matching any keyword" {
            $obj1 = [PSCustomObject]@{ Name = "apple" }
            $obj2 = [PSCustomObject]@{ Name = "banana" }
            $obj3 = [PSCustomObject]@{ Name = "cherry" }
            $list = $obj1, $obj2, $obj3
            $res = $list | Find-ObjectByName -SearchTerms "apple", "cherry"
            $res.Count | Should -Be 2
            $res | Should -Contain $obj1
            $res | Should -Contain $obj3
        }
    }

    Context "Explicit AND Logic" {
        It "should return objects matching all keywords" {
            $obj1 = [PSCustomObject]@{ Name = "apple pie" }
            $obj2 = [PSCustomObject]@{ Name = "apple tart" }
            $obj3 = [PSCustomObject]@{ Name = "cherry pie" }
            $list = $obj1, $obj2, $obj3
            $res = $list | Find-ObjectByName -SearchTerms "apple", "and", "pie"
            $res.Count | Should -Be 1
            $res | Should -Contain $obj1
        }
        It "should return nothing if AND condition fails" {
            $obj = [PSCustomObject]@{ Name = "apple pie" }
            $res = $obj | Find-ObjectByName -SearchTerms "apple", "and", "tart"
            $null -eq $res | Should -Be $true
        }
    }

    Context "Explicit OR Logic" {
        It "should return objects matching any keyword with explicit 'or'" {
            $obj1 = [PSCustomObject]@{ Name = "apple" }
            $obj2 = [PSCustomObject]@{ Name = "banana" }
            $obj3 = [PSCustomObject]@{ Name = "cherry" }
            $list = $obj1, $obj2, $obj3
            $res = $list | Find-ObjectByName -SearchTerms "apple", "or", "cherry"
            $res.Count | Should -Be 2
        }
    }

    Context "Edge Cases and Errors" {
        It "should handle null input gracefully" {
            $res = $null | Find-ObjectByName -SearchTerms "test"
            $null -eq $res | Should -Be $true
        }

        It "should ignore objects without a Name property" {
            $obj = [PSCustomObject]@{ Value = "testObject" }
            $res = $obj | Find-ObjectByName -SearchTerms "test"
            $null -eq $res | Should -Be $true
        }

        It "should skip objects with empty or whitespace Name property" {
            $obj1 = [PSCustomObject]@{ Name = "" }
            $obj2 = [PSCustomObject]@{ Name = "   " }
            $list = $obj1, $obj2
            $res = $list | Find-ObjectByName -SearchTerms "test"
            $null -eq $res | Should -Be $true
        }

        It "should throw an error if no valid keywords are provided" {
            { Get-Process | Find-ObjectByName -SearchTerms "or" } | Should -Throw "No valid search keywords provided in '-SearchTerms' after parsing operators. Please provide at least one keyword."
            { Get-Process | Find-ObjectByName -SearchTerms "and" } | Should -Throw "No valid search keywords provided in '-SearchTerms' after parsing operators. Please provide at least one keyword."
        }
    }
}
