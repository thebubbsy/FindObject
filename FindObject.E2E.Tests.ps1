#Requires -Modules Pester

<#
.SYNOPSIS
    Comprehensive Opaque-Box End-to-End (E2E) Test Suite for FindObject.

.DESCRIPTION
    Validates FindObject v2.0 across 4 Tiers:
      - Tier 1: Feature Coverage (Equivalence classes covering F1 through F12)
      - Tier 2: Boundary & Corner Cases (Extreme limits, empty/whitespace, edge inputs)
      - Tier 3: Cross-Feature Combinations (Pairwise & multi-feature interactions)
      - Tier 4: Real-World Application Scenarios (Realistic sysadmin/DevSecOps workloads)

    Derived strictly from ORIGINAL_REQUEST.md and PROJECT.md.
    Maintained independently by E2E Test Writer.
#>

BeforeAll {
    # Isolate module path to local AppData to prevent OneDrive dehydration locks
    $env:PSModulePath = "C:\Users\Tony\AppData\Local\PowerShell\Modules;" + $env:PSModulePath
    Import-Module "C:\Users\Tony\AppData\Local\PowerShell\Modules\Pester\5.6.1\Pester.psd1" -Force

    $script:ModuleDir = $PSScriptRoot
    $script:CoreManifest = Join-Path $script:ModuleDir "FindObject.psd1"
    $script:CorePsm1 = Join-Path $script:ModuleDir "FindObject.psm1"
    $script:IntuneManifest = Join-Path $script:ModuleDir "FindObject.Intune.psd1"
    $script:IntunePsm1 = Join-Path $script:ModuleDir "FindObject.Intune.psm1"

    # Reset any active module in session
    Get-Module FindObject, FindObject.Intune | Remove-Module -Force -ErrorAction SilentlyContinue

    if (Test-Path $script:CoreManifest) {
        Import-Module $script:CoreManifest -Force
    } else {
        Import-Module $script:CorePsm1 -Force
    }
}

Describe "FindObject E2E Test Suite" -Tags "E2E" {

    AfterEach {
        # Ensure config session defaults are restored if altered
        Set-FindObjectConfig -Mode Contains -Property 'Name' -ErrorAction SilentlyContinue | Out-Null
    }

    # =========================================================================
    # TIER 1: FEATURE COVERAGE (F1 to F12)
    # =========================================================================
    Context "Tier 1: Feature Coverage" -Tags "Tier1" {

        # --- F1: Quoted Phrase Preservation ---
        Context "F1: Quoted Phrase Preservation" {
            It "F1-1: Preserves double-quoted multi-word phrase intact" {
                $items = @(
                    [PSCustomObject]@{ Name = "Google Chrome Setup" }
                    [PSCustomObject]@{ Name = "Google Browser Setup" }
                    [PSCustomObject]@{ Name = "Chrome Extension Host" }
                )
                $res = @($items | Find-ObjectByName '"Google Chrome"')
                $res.Count | Should -Be 1
                $res[0].Name | Should -Be "Google Chrome Setup"
            }

            It "F1-2: Preserves single-quoted multi-word phrase intact" {
                $items = @(
                    [PSCustomObject]@{ Name = "Visual Studio Code" }
                    [PSCustomObject]@{ Name = "Visual Studio 2022" }
                    [PSCustomObject]@{ Name = "Source Code Editor" }
                )
                $res = @($items | Find-ObjectByName "'Visual Studio Code'")
                $res.Count | Should -Be 1
                $res[0].Name | Should -Be "Visual Studio Code"
            }

            It "F1-3: Treats boolean keywords inside quotes as literal text" {
                $items = @(
                    [PSCustomObject]@{ Name = "Apple and Banana Smoothie" }
                    [PSCustomObject]@{ Name = "Apple Pie" }
                    [PSCustomObject]@{ Name = "Banana Split" }
                )
                $res = @($items | Find-ObjectByName '"Apple and Banana"')
                $res.Count | Should -Be 1
                $res[0].Name | Should -Be "Apple and Banana Smoothie"
            }

            It "F1-4: Preserves phrases containing punctuation and version symbols" {
                $items = @(
                    [PSCustomObject]@{ Name = "Release v2.0.0 (Stable)" }
                    [PSCustomObject]@{ Name = "Release v2.0.0 (Beta)" }
                    [PSCustomObject]@{ Name = "Release v1.0.0 (Stable)" }
                )
                $res = @($items | Find-ObjectByName '"v2.0.0 (Stable)"')
                $res.Count | Should -Be 1
                $res[0].Name | Should -Be "Release v2.0.0 (Stable)"
            }

            It "F1-5: Quoted phrase combined with boolean operator preserved as discrete token" {
                $items = @(
                    [PSCustomObject]@{ Name = "Google Chrome Setup" }
                    [PSCustomObject]@{ Name = "Google Chrome Portable" }
                    [PSCustomObject]@{ Name = "Mozilla Firefox Setup" }
                )
                $res = @($items | Find-ObjectByName '"Google Chrome" AND Setup')
                $res.Count | Should -Be 1
                $res[0].Name | Should -Be "Google Chrome Setup"
            }
        }

        # --- F2: Boolean Operator Lexing ---
        Context "F2: Boolean Operator Lexing" {
            It "F2-1: Recognizes AND case-insensitively" {
                $items = @(
                    [PSCustomObject]@{ Name = "apple pie" }
                    [PSCustomObject]@{ Name = "apple tart" }
                )
                $res1 = @($items | Find-ObjectByName "apple AND pie")
                $res2 = @($items | Find-ObjectByName "apple and pie")
                $res3 = @($items | Find-ObjectByName "apple And pie")
                $res1.Count | Should -Be 1
                $res2.Count | Should -Be 1
                $res3.Count | Should -Be 1
            }

            It "F2-2: Recognizes OR case-insensitively" {
                $items = @(
                    [PSCustomObject]@{ Name = "apple pie" }
                    [PSCustomObject]@{ Name = "banana bread" }
                    [PSCustomObject]@{ Name = "cherry tart" }
                )
                $res1 = @($items | Find-ObjectByName "apple OR banana")
                $res2 = @($items | Find-ObjectByName "apple or banana")
                $res1.Count | Should -Be 2
                $res2.Count | Should -Be 2
            }

            It "F2-3: Array syntax with boolean operators matches natural language string" {
                $items = @(
                    [PSCustomObject]@{ Name = "apple pie" }
                    [PSCustomObject]@{ Name = "cherry tart" }
                )
                $resArray = @($items | Find-ObjectByName @("apple", "OR", "cherry"))
                $resString = @($items | Find-ObjectByName "apple OR cherry")
                $resArray.Count | Should -Be 2
                $resString.Count | Should -Be 2
            }

            It "F2-4: Words containing operator substrings are treated as literals" {
                $items = @(
                    [PSCustomObject]@{ Name = "BAND_LEADER" }
                    [PSCustomObject]@{ Name = "STAND_ALONE" }
                    [PSCustomObject]@{ Name = "NOTIFY_SERVICE" }
                    [PSCustomObject]@{ Name = "TORNADO_WATCH" }
                )
                $res1 = @($items | Find-ObjectByName "BAND")
                $res2 = @($items | Find-ObjectByName "NOTIFY")
                $res1.Count | Should -Be 1
                $res1[0].Name | Should -Be "BAND_LEADER"
                $res2.Count | Should -Be 1
                $res2[0].Name | Should -Be "NOTIFY_SERVICE"
            }

            It "F2-5: Multiple internal spaces around operators are handled cleanly" {
                $items = @(
                    [PSCustomObject]@{ Name = "alpha beta gamma" }
                    [PSCustomObject]@{ Name = "alpha delta" }
                )
                $res = @($items | Find-ObjectByName "alpha    AND    gamma")
                $res.Count | Should -Be 1
                $res[0].Name | Should -Be "alpha beta gamma"
            }
        }

        # --- F3: Boolean Operator Precedence ---
        Context "F3: Boolean Operator Precedence" {
            It "F3-1: Enforces NOT > AND > OR for A OR B AND C" {
                # A OR (B AND C):
                # item1: A=True, B=False, C=False -> True
                # item2: A=False, B=True, C=True -> True
                # item3: A=False, B=True, C=False -> False (under naive left-to-right (A OR B) AND C, item1 would be False!)
                $items = @(
                    [PSCustomObject]@{ Name = "alpha" }
                    [PSCustomObject]@{ Name = "beta gamma" }
                    [PSCustomObject]@{ Name = "beta only" }
                )
                $res = @($items | Find-ObjectByName "alpha OR beta AND gamma")
                $res.Count | Should -Be 2
                $names = $res | ForEach-Object { $_.Name }
                $names | Should -Contain "alpha"
                $names | Should -Contain "beta gamma"
                $names | Should -Not -Contain "beta only"
            }

            It "F3-2: Precedence for A AND B OR C AND D evaluates as (A AND B) OR (C AND D)" {
                $items = @(
                    [PSCustomObject]@{ Name = "prod web" }
                    [PSCustomObject]@{ Name = "dev db" }
                    [PSCustomObject]@{ Name = "prod db" }
                    [PSCustomObject]@{ Name = "dev web" }
                )
                $res = @($items | Find-ObjectByName "prod AND web OR dev AND db")
                $res.Count | Should -Be 2
                $names = $res | ForEach-Object { $_.Name }
                $names | Should -Contain "prod web"
                $names | Should -Contain "dev db"
            }

            It "F3-3: NOT binds tighter than AND: NOT A AND B evaluates as (NOT A) AND B" {
                $items = @(
                    [PSCustomObject]@{ Name = "beta" }
                    [PSCustomObject]@{ Name = "alpha beta" }
                    [PSCustomObject]@{ Name = "alpha" }
                )
                $res = @($items | Find-ObjectByName "NOT alpha AND beta")
                $res.Count | Should -Be 1
                $res[0].Name | Should -Be "beta"
            }

            It "F3-4: NOT binds tighter than OR: A OR NOT B" {
                $items = @(
                    [PSCustomObject]@{ Name = "apple" }
                    [PSCustomObject]@{ Name = "banana" }
                    [PSCustomObject]@{ Name = "cherry" }
                )
                # Matches anything with apple, OR anything NOT containing banana (cherry has no banana -> matches)
                $res = @($items | Find-ObjectByName "apple OR NOT banana")
                $names = $res | ForEach-Object { $_.Name }
                $names | Should -Contain "apple"
                $names | Should -Contain "cherry"
                $names | Should -Not -Contain "banana"
            }

            It "F3-5: Mixed chain: A OR B AND NOT C" {
                $items = @(
                    [PSCustomObject]@{ Name = "first" }
                    [PSCustomObject]@{ Name = "second active" }
                    [PSCustomObject]@{ Name = "second inactive" }
                )
                # first matches; second active matches; second inactive rejected by NOT inactive
                $res = @($items | Find-ObjectByName "first OR second AND NOT inactive")
                $res.Count | Should -Be 2
                $names = $res | ForEach-Object { $_.Name }
                $names | Should -Contain "first"
                $names | Should -Contain "second active"
            }
        }

        # --- F4: Expression Grouping ---
        Context "F4: Expression Grouping" {
            It "F4-1: Parentheses override precedence: (A OR B) AND C" {
                $items = @(
                    [PSCustomObject]@{ Name = "apple pie" }
                    [PSCustomObject]@{ Name = "cherry pie" }
                    [PSCustomObject]@{ Name = "apple tart" }
                    [PSCustomObject]@{ Name = "banana bread" }
                )
                $res = @($items | Find-ObjectByName "(apple OR cherry) AND pie")
                $res.Count | Should -Be 2
                $names = $res | ForEach-Object { $_.Name }
                $names | Should -Contain "apple pie"
                $names | Should -Contain "cherry pie"
                $names | Should -Not -Contain "apple tart"
            }

            It "F4-2: Nested parentheses evaluate innermost first" {
                $items = @(
                    [PSCustomObject]@{ Name = "apple sweet red" }
                    [PSCustomObject]@{ Name = "banana sweet yellow" }
                    [PSCustomObject]@{ Name = "lemon sour yellow" }
                    [PSCustomObject]@{ Name = "grape tart purple" }
                )
                $res = @($items | Find-ObjectByName "((apple OR banana) AND sweet) OR lemon")
                $res.Count | Should -Be 3
                $names = $res | ForEach-Object { $_.Name }
                $names | Should -Contain "apple sweet red"
                $names | Should -Contain "banana sweet yellow"
                $names | Should -Contain "lemon sour yellow"
                $names | Should -Not -Contain "grape tart purple"
            }

            It "F4-3: Parentheses enclosing quoted phrases" {
                $items = @(
                    [PSCustomObject]@{ Name = "Google Chrome 120" }
                    [PSCustomObject]@{ Name = "Mozilla Firefox 120" }
                    [PSCustomObject]@{ Name = "Google Chrome 119" }
                )
                $res = @($items | Find-ObjectByName '("Google Chrome" OR "Mozilla Firefox") AND 120')
                $res.Count | Should -Be 2
                $names = $res | ForEach-Object { $_.Name }
                $names | Should -Contain "Google Chrome 120"
                $names | Should -Contain "Mozilla Firefox 120"
            }

            It "F4-4: Grouping with negation: NOT (A OR B)" {
                $items = @(
                    [PSCustomObject]@{ Name = "prod server" }
                    [PSCustomObject]@{ Name = "dev server" }
                    [PSCustomObject]@{ Name = "test server" }
                    [PSCustomObject]@{ Name = "stg server" }
                )
                $res = @($items | Find-ObjectByName "NOT (dev OR test)")
                $res.Count | Should -Be 2
                $names = $res | ForEach-Object { $_.Name }
                $names | Should -Contain "prod server"
                $names | Should -Contain "stg server"
            }

            It "F4-5: Multiple disjoint parenthesized groups: (A OR B) AND (C OR D)" {
                $items = @(
                    [PSCustomObject]@{ Name = "alpha gamma" }
                    [PSCustomObject]@{ Name = "alpha delta" }
                    [PSCustomObject]@{ Name = "beta gamma" }
                    [PSCustomObject]@{ Name = "alpha epsilon" }
                )
                $res = @($items | Find-ObjectByName "(alpha OR beta) AND (gamma OR delta)")
                $res.Count | Should -Be 3
                $names = $res | ForEach-Object { $_.Name }
                $names | Should -Contain "alpha gamma"
                $names | Should -Contain "alpha delta"
                $names | Should -Contain "beta gamma"
                $names | Should -Not -Contain "alpha epsilon"
            }
        }

        # --- F5: Unary NOT Evaluation ---
        Context "F5: Unary NOT Evaluation" {
            It "F5-1: Leading unary NOT filters matching objects" {
                $items = @(
                    [PSCustomObject]@{ Name = "chrome" }
                    [PSCustomObject]@{ Name = "chrome helper" }
                    [PSCustomObject]@{ Name = "firefox" }
                )
                $res = @($items | Find-ObjectByName "NOT helper")
                $res.Count | Should -Be 2
                $names = $res | ForEach-Object { $_.Name }
                $names | Should -Contain "chrome"
                $names | Should -Contain "firefox"
                $names | Should -Not -Contain "chrome helper"
            }

            It "F5-2: Unary NOT in conjunction: A AND NOT B" {
                $items = @(
                    [PSCustomObject]@{ Name = "apple pie" }
                    [PSCustomObject]@{ Name = "cherry pie" }
                    [PSCustomObject]@{ Name = "apple tart" }
                )
                $res = @($items | Find-ObjectByName "pie AND NOT cherry")
                $res.Count | Should -Be 1
                $res[0].Name | Should -Be "apple pie"
            }

            It "F5-3: Unary NOT in disjunction: A OR NOT B" {
                $items = @(
                    [PSCustomObject]@{ Name = "primary" }
                    [PSCustomObject]@{ Name = "backup active" }
                    [PSCustomObject]@{ Name = "backup idle" }
                )
                $res = @($items | Find-ObjectByName "primary OR NOT idle")
                $res.Count | Should -Be 2
                $names = $res | ForEach-Object { $_.Name }
                $names | Should -Contain "primary"
                $names | Should -Contain "backup active"
            }

            It "F5-4: Conjunction of multiple NOT clauses: NOT dev AND NOT stg" {
                $items = @(
                    [PSCustomObject]@{ Name = "prod" }
                    [PSCustomObject]@{ Name = "dev" }
                    [PSCustomObject]@{ Name = "stg" }
                )
                $res = @($items | Find-ObjectByName "NOT dev AND NOT stg")
                $res.Count | Should -Be 1
                $res[0].Name | Should -Be "prod"
            }

            It "F5-5: Unary NOT targeted with -Property" {
                $items = @(
                    [PSCustomObject]@{ Title = "Manager"; Role = "Admin" }
                    [PSCustomObject]@{ Title = "Engineer"; Role = "User" }
                    [PSCustomObject]@{ Title = "Lead"; Role = "Admin" }
                )
                $res = @($items | Find-ObjectByName "NOT Admin" -Property Role)
                $res.Count | Should -Be 1
                $res[0].Title | Should -Be "Engineer"
            }
        }

        # --- F6: Dotted Property Paths ---
        Context "F6: Dotted Property Paths" {
            It "F6-1: Resolves 2-level dotted property path (Parent.Child)" {
                $items = @(
                    [PSCustomObject]@{ Server = [PSCustomObject]@{ Hostname = "db-01.internal" } }
                    [PSCustomObject]@{ Server = [PSCustomObject]@{ Hostname = "web-01.internal" } }
                )
                $res = @($items | Find-ObjectByName "db-01" -Property "Server.Hostname")
                $res.Count | Should -Be 1
                $res[0].Server.Hostname | Should -Be "db-01.internal"
            }

            It "F6-2: Resolves 3-level dotted property path (A.B.C)" {
                $items = @(
                    [PSCustomObject]@{ Org = [PSCustomObject]@{ Team = [PSCustomObject]@{ Lead = "Alice" } } }
                    [PSCustomObject]@{ Org = [PSCustomObject]@{ Team = [PSCustomObject]@{ Lead = "Bob" } } }
                )
                $res = @($items | Find-ObjectByName "Alice" -Property "Org.Team.Lead")
                $res.Count | Should -Be 1
                $res[0].Org.Team.Lead | Should -Be "Alice"
            }

            It "F6-3: Unwraps collections in dotted paths (Items.Name)" {
                $items = @(
                    [PSCustomObject]@{
                        GroupId = 101
                        Members = @(
                            [PSCustomObject]@{ Username = "jsmith" }
                            [PSCustomObject]@{ Username = "asmith" }
                        )
                    }
                    [PSCustomObject]@{
                        GroupId = 102
                        Members = @(
                            [PSCustomObject]@{ Username = "bwhite" }
                        )
                    }
                )
                $res = @($items | Find-ObjectByName "asmith" -Property "Members.Username")
                $res.Count | Should -Be 1
                $res[0].GroupId | Should -Be 101
            }

            It "F6-4: Missing intermediate property returns empty without error" {
                $items = @(
                    [PSCustomObject]@{ Config = $null }
                    [PSCustomObject]@{ Other = "Val" }
                )
                { $script:res = @($items | Find-ObjectByName "Target" -Property "Config.Setting.Name") } | Should -Not -Throw
                $script:res.Count | Should -Be 0
            }

            It "F6-5: Falls back to literal property if property name itself contains dots" {
                $obj = [PSCustomObject]@{ "System.Core.Version" = "5.1.0" }
                $res = @($obj | Find-ObjectByName "5.1.0" -Property "System.Core.Version")
                $res.Count | Should -Be 1
            }
        }

        # --- F7: Wildcard Non-String Inspection ---
        Context "F7: Wildcard Non-String Inspection" {
            It "F7-1: -Property * inspects integer properties without dropping" {
                $items = @(
                    [PSCustomObject]@{ Name = "WebSvc"; Port = 8080 }
                    [PSCustomObject]@{ Name = "DbSvc"; Port = 5432 }
                )
                $res = @($items | Find-ObjectByName "8080" -Property *)
                $res.Count | Should -Be 1
                $res[0].Name | Should -Be "WebSvc"
            }

            It "F7-2: -Property * inspects DateTime properties" {
                $date1 = [datetime]"2026-05-15T12:00:00"
                $date2 = [datetime]"2024-01-01T08:00:00"
                $items = @(
                    [PSCustomObject]@{ Name = "BackupA"; CreatedAt = $date1 }
                    [PSCustomObject]@{ Name = "BackupB"; CreatedAt = $date2 }
                )
                $res = @($items | Find-ObjectByName "2026" -Property *)
                $res.Count | Should -Be 1
                $res[0].Name | Should -Be "BackupA"
            }

            It "F7-3: -Property * inspects Boolean properties" {
                $items = @(
                    [PSCustomObject]@{ Name = "FeatureA"; IsEnabled = $true }
                    [PSCustomObject]@{ Name = "FeatureB"; IsEnabled = $false }
                )
                $res = @($items | Find-ObjectByName "True" -Property *)
                $res.Count | Should -Be 1
                $res[0].Name | Should -Be "FeatureA"
            }

            It "F7-4: -Property * inspects Guid properties" {
                $guidTarget = [guid]::Parse("12345678-aaaa-bbbb-cccc-111122223333")
                $guidOther  = [guid]::Parse("99999999-0000-0000-0000-999999999999")
                $items = @(
                    [PSCustomObject]@{ Name = "ObjA"; Id = $guidTarget }
                    [PSCustomObject]@{ Name = "ObjB"; Id = $guidOther }
                )
                $res = @($items | Find-ObjectByName "12345678" -Property *)
                $res.Count | Should -Be 1
                $res[0].Name | Should -Be "ObjA"
            }

            It "F7-5: -Property * inspects mixed PSCustomObject across diverse property types" {
                $items = @(
                    [PSCustomObject]@{
                        Host = "srv-app-01"
                        Port = 443
                        Active = $true
                        Score = 98.6
                    }
                    [PSCustomObject]@{
                        Host = "srv-app-02"
                        Port = 80
                        Active = $false
                        Score = 45.2
                    }
                )
                $res = @($items | Find-ObjectByName "98.6" -Property *)
                $res.Count | Should -Be 1
                $res[0].Host | Should -Be "srv-app-01"
            }
        }

        # --- F8: Array Element Evaluation ---
        Context "F8: Array Element Evaluation" {
            It "F8-1: Evaluates individual array elements in Exact mode" {
                $items = @(
                    [PSCustomObject]@{ Name = "SvcA"; Tags = @("production", "pci") }
                    [PSCustomObject]@{ Name = "SvcB"; Tags = @("staging", "internal") }
                )
                $res = @($items | Find-ObjectByName "production" -Property Tags -Mode Exact)
                $res.Count | Should -Be 1
                $res[0].Name | Should -Be "SvcA"
            }

            It "F8-2: Rejects concatenated multi-element strings in Exact mode" {
                $items = @(
                    [PSCustomObject]@{ Name = "SvcA"; Tags = @("production", "pci") }
                )
                # If flattened destructively to "production pci", exact match would fail
                $res = @($items | Find-ObjectByName "production pci" -Property Tags -Mode Exact)
                $res.Count | Should -Be 0
            }

            It "F8-3: Evaluates individual array elements in StartsWith mode" {
                $items = @(
                    [PSCustomObject]@{ Name = "PkgA"; Dependencies = @("System.Text.Json", "Microsoft.Extensions") }
                    [PSCustomObject]@{ Name = "PkgB"; Dependencies = @("Newtonsoft.Json", "NUnit") }
                )
                $res = @($items | Find-ObjectByName "System" -Property Dependencies -Mode StartsWith)
                $res.Count | Should -Be 1
                $res[0].Name | Should -Be "PkgA"
            }

            It "F8-4: Prevents cross-element boundary substring leakage" {
                $items = @(
                    [PSCustomObject]@{ Name = "Item1"; Tags = @("alpha", "beta") }
                )
                # If flattened to "alphabeta", searching "habe" in Contains mode would erroneously match
                $res = @($items | Find-ObjectByName "habe" -Property Tags -Mode Contains)
                $res.Count | Should -Be 0
            }

            It "F8-5: Evaluates array containing numeric items" {
                $items = @(
                    [PSCustomObject]@{ Id = "A"; StatusCodes = @(200, 204, 301) }
                    [PSCustomObject]@{ Id = "B"; StatusCodes = @(400, 404, 500) }
                )
                $res = @($items | Find-ObjectByName "204" -Property StatusCodes -Mode Exact)
                $res.Count | Should -Be 1
                $res[0].Id | Should -Be "A"
            }
        }

        # --- F9: Regex Pipeline Resilience ---
        Context "F9: Regex Pipeline Resilience" {
            It "F9-1: Emits terminating error on invalid regex syntax before pipeline streaming" {
                $data = 1..50 | ForEach-Object { [PSCustomObject]@{ Name = "item$_" } }
                { @($data | Find-ObjectByName "[" -Mode Regex) } | Should -Throw
            }

            It "F9-2: Halts immediately on invalid regex quantifier without emitting items" {
                $items = @(
                    [PSCustomObject]@{ Name = "valid1" }
                    [PSCustomObject]@{ Name = "valid2" }
                )
                { @($items | Find-ObjectByName "+abc" -Mode Regex) } | Should -Throw
            }

            It "F9-3: Matches valid .NET regex patterns with character classes" {
                $items = @(
                    [PSCustomObject]@{ Name = "audit_2026_09_13.log" }
                    [PSCustomObject]@{ Name = "audit_report.docx" }
                )
                $res = @($items | Find-ObjectByName 'audit_\d{4}_\d{2}_\d{2}\.log' -Mode Regex)
                $res.Count | Should -Be 1
                $res[0].Name | Should -Be "audit_2026_09_13.log"
            }

            It "F9-4: Regex mode respects -CaseSensitive" {
                $items = @(
                    [PSCustomObject]@{ Name = "ERROR_EVENT" }
                    [PSCustomObject]@{ Name = "error_event" }
                )
                $res = @($items | Find-ObjectByName "^ERROR" -Mode Regex -CaseSensitive)
                $res.Count | Should -Be 1
                $res[0].Name | Should -Be "ERROR_EVENT"
            }

            It "F9-5: Invalid regex in boolean clause terminates cleanly in begin" {
                $items = @([PSCustomObject]@{ Name = "test" })
                { @($items | Find-ObjectByName "valid AND [unclosed" -Mode Regex) } | Should -Throw
            }
        }

        # --- F10: Clean Highlight Pipeline ---
        Context "F10: Clean Highlight Pipeline" {
            It "F10-1: -Highlight emits objects via Success stream without Write-Host pollution" {
                $infoStream = [System.Collections.ArrayList]::new()
                $obj = [PSCustomObject]@{ Name = "Production Server" }
                $res = @($obj | Find-ObjectByName "Server" -Highlight -InformationAction Continue -InformationVariable infoStream)
                $res.Count | Should -Be 1
                # Must not write raw lines to Information/Host stream
                $infoStream.Count | Should -Be 0
            }

            It "F10-2: -Highlight passes object cleanly through to Format-Table" {
                $items = @(
                    [PSCustomObject]@{ Name = "TestApp"; Status = "Running" }
                )
                $table = $null
                { $script:table = $items | Find-ObjectByName "TestApp" -Highlight | Format-Table | Out-String } | Should -Not -Throw
                $script:table | Should -Not -BeNullOrEmpty
            }

            It "F10-3: Highlighted property contains ANSI escape formatting sequence" {
                $obj = [PSCustomObject]@{ Name = "HighlightTarget" }
                $res = @($obj | Find-ObjectByName "Target" -Highlight)
                $res.Count | Should -Be 1
                # ANSI ESC is [char]27: \e[1;33m
                $esc = [char]27
                $res[0].Name | Should -Match ([regex]::Escape("${esc}[1;33m"))
            }

            It "F10-4: Capturing highlighted pipeline output in variable preserves object" {
                $items = @(
                    [PSCustomObject]@{ Name = "WorkerNode1" }
                    [PSCustomObject]@{ Name = "MasterNode1" }
                )
                $captured = @($items | Find-ObjectByName "Worker" -Highlight)
                $captured.Count | Should -Be 1
                $captured[0] | Should -Not -BeNullOrEmpty
            }

            It "F10-5: Highlighting handles multiple occurrences within target property" {
                $obj = [PSCustomObject]@{ Name = "echo echo echo" }
                $res = @($obj | Find-ObjectByName "echo" -Highlight)
                $res.Count | Should -Be 1
                $esc = [char]27
                $matches = [regex]::Matches($res[0].Name, [regex]::Escape("${esc}[1;33m"))
                $matches.Count | Should -Be 3
            }
        }

        # --- F11: Intune Submodule Extraction ---
        Context "F11: Intune Submodule Extraction" {
            It "F11-1: Submodule manifest FindObject.Intune.psd1 exists" {
                Test-Path $script:IntuneManifest | Should -BeTrue
            }

            It "F11-2: Submodule script FindObject.Intune.psm1 exists" {
                Test-Path $script:IntunePsm1 | Should -BeTrue
            }

            It "F11-3: Submodule exports all 8 Intune cmdlets" {
                if (-not (Test-Path $script:IntuneManifest)) {
                    Test-Path $script:IntuneManifest | Should -BeTrue
                } else {
                    $manifest = Import-PowerShellDataFile $script:IntuneManifest
                    $expected = @(
                        'Connect-FindObjectGraph', 'Disconnect-FindObjectGraph',
                        'Get-IntuneDevice', 'Get-IntuneApp', 'Get-IntuneCompliancePolicy',
                        'Get-IntuneConfigProfile', 'Get-IntuneAutopilotDevice', 'Get-IntuneEnrollment'
                    )
                    foreach ($cmd in $expected) {
                        $manifest.FunctionsToExport | Should -Contain $cmd
                    }
                }
            }

            It "F11-4: Submodule exports gid alias for Get-IntuneDevice" {
                if (-not (Test-Path $script:IntuneManifest)) {
                    Test-Path $script:IntuneManifest | Should -BeTrue
                } else {
                    $manifest = Import-PowerShellDataFile $script:IntuneManifest
                    $manifest.AliasesToExport | Should -Contain 'gid'
                }
            }

            It "F11-5: Get-IntuneDevice raises auth guard exception when disconnected" {
                if (-not (Test-Path $script:IntunePsm1)) {
                    Test-Path $script:IntunePsm1 | Should -BeTrue
                } else {
                    Import-Module $script:IntunePsm1 -Force
                    Disconnect-FindObjectGraph -ErrorAction SilentlyContinue
                    { Get-IntuneDevice } | Should -Throw "*Connect-FindObjectGraph*"
                }
            }
        }

        # --- F12: Core Module Isolation ---
        Context "F12: Core Module Isolation" {
            It "F12-1: Core manifest exports exactly 3 core functions" {
                $manifest = Import-PowerShellDataFile $script:CoreManifest
                $manifest.FunctionsToExport.Count | Should -Be 3
                $manifest.FunctionsToExport | Should -Contain 'Find-ObjectByName'
                $manifest.FunctionsToExport | Should -Contain 'Get-FindObjectConfig'
                $manifest.FunctionsToExport | Should -Contain 'Set-FindObjectConfig'
            }

            It "F12-2: Core manifest exports 0 Intune cmdlets" {
                $manifest = Import-PowerShellDataFile $script:CoreManifest
                $intuneCmds = @($manifest.FunctionsToExport | Where-Object { $_ -like 'Get-Intune*' -or $_ -like '*-FindObjectGraph' })
                $intuneCmds.Count | Should -Be 0
            }

            It "F12-3: Core manifest exports fob alias and 0 Intune aliases" {
                $manifest = Import-PowerShellDataFile $script:CoreManifest
                $manifest.AliasesToExport | Should -Contain 'fob'
                $manifest.AliasesToExport | Should -Not -Contain 'gid'
            }

            It "F12-4: Core engine FindObject.psm1 contains 0 direct Microsoft Graph endpoint URIs" {
                $content = Get-Content -LiteralPath $script:CorePsm1 -Raw
                $content | Should -Not -Match 'https://graph\.microsoft\.com'
            }

            It "F12-5: Core module operates completely standalone without Intune dependencies" {
                Import-Module $script:CoreManifest -Force
                $res = [PSCustomObject]@{ Name = "IsolatedCoreTest" } | fob "Isolated"
                $res.Name | Should -Be "IsolatedCoreTest"
            }
        }
    }

    # =========================================================================
    # TIER 2: BOUNDARY & CORNER CASES (F1 to F12)
    # =========================================================================
    Context "Tier 2: Boundary & Corner Cases" -Tags "Tier2" {

        # --- F1 Boundary ---
        Context "F1: Quoted Phrase Boundaries" {
            It "T2-F1-1: Empty double quotes in query handled gracefully" {
                $items = @([PSCustomObject]@{ Name = "test item" })
                { $script:res = @($items | Find-ObjectByName '"" test') } | Should -Not -Throw
                $script:res.Count | Should -Be 1
            }

            It "T2-F1-2: Whitespace-only quotes in query handled gracefully" {
                $items = @([PSCustomObject]@{ Name = "test item" })
                { $script:res = @($items | Find-ObjectByName '"   " test') } | Should -Not -Throw
                $script:res.Count | Should -Be 1
            }

            It "T2-F1-3: Unclosed quote throws descriptive syntax error" {
                $items = @([PSCustomObject]@{ Name = "test item" })
                { @($items | Find-ObjectByName '"unclosed phrase') } | Should -Throw
            }

            It "T2-F1-4: Adjacent quoted phrases parsed as two distinct phrases" {
                $items = @(
                    [PSCustomObject]@{ Name = "Alpha Beta Gamma Delta" }
                    [PSCustomObject]@{ Name = "Alpha Gamma" }
                )
                $res = @($items | Find-ObjectByName '"Alpha Beta" "Gamma Delta"')
                $res.Count | Should -Be 1
                $res[0].Name | Should -Be "Alpha Beta Gamma Delta"
            }

            It "T2-F1-5: Quoted phrase at extreme string boundaries (start and end)" {
                $items = @(
                    [PSCustomObject]@{ Name = "start middle end" }
                )
                $res1 = @($items | Find-ObjectByName '"start middle"')
                $res2 = @($items | Find-ObjectByName '"middle end"')
                $res1.Count | Should -Be 1
                $res2.Count | Should -Be 1
            }
        }

        # --- F2 Boundary ---
        Context "F2: Boolean Operator Lexing Boundaries" {
            It "T2-F2-1: Trailing boolean operator throws syntax error" {
                $items = @([PSCustomObject]@{ Name = "apple" })
                { @($items | Find-ObjectByName "apple AND") } | Should -Throw
            }

            It "T2-F2-2: Leading binary operator throws syntax error" {
                $items = @([PSCustomObject]@{ Name = "banana" })
                { @($items | Find-ObjectByName "OR banana") } | Should -Throw
            }

            It "T2-F2-3: Consecutive binary operators throw syntax error" {
                $items = @([PSCustomObject]@{ Name = "cherry" })
                { @($items | Find-ObjectByName "apple AND OR banana") } | Should -Throw
            }

            It "T2-F2-4: Operator-only input string throws descriptive error" {
                $items = @([PSCustomObject]@{ Name = "something" })
                { @($items | Find-ObjectByName "AND OR NOT") } | Should -Throw
            }

            It "T2-F2-5: Mixed case boolean permutations (aNd, oR, nOt)" {
                $items = @(
                    [PSCustomObject]@{ Name = "alpha beta" }
                    [PSCustomObject]@{ Name = "gamma" }
                )
                $res = @($items | Find-ObjectByName "alpha aNd beta oR nOt gamma")
                $res.Count | Should -Be 1
                $res[0].Name | Should -Be "alpha beta"
            }
        }

        # --- F3 Boundary ---
        Context "F3: Boolean Precedence Boundaries" {
            It "T2-F3-1: Long 6-term unparenthesized chain respects precedence" {
                # A OR B AND C OR D AND E OR F
                # (A) OR (B AND C) OR (D AND E) OR (F)
                $items = @(
                    [PSCustomObject]@{ Name = "A" }
                    [PSCustomObject]@{ Name = "B C" }
                    [PSCustomObject]@{ Name = "D E" }
                    [PSCustomObject]@{ Name = "F" }
                    [PSCustomObject]@{ Name = "B only" }
                    [PSCustomObject]@{ Name = "D only" }
                )
                $res = @($items | Find-ObjectByName "A OR B AND C OR D AND E OR F")
                $res.Count | Should -Be 4
                $names = $res | ForEach-Object { $_.Name }
                $names | Should -Contain "A"
                $names | Should -Contain "B C"
                $names | Should -Contain "D E"
                $names | Should -Contain "F"
                $names | Should -Not -Contain "B only"
            }

            It "T2-F3-2: Contradictory condition (A AND NOT A) returns empty set" {
                $items = @(
                    [PSCustomObject]@{ Name = "item" }
                    [PSCustomObject]@{ Name = "item other" }
                )
                $res = @($items | Find-ObjectByName "item AND NOT item")
                $res.Count | Should -Be 0
            }

            It "T2-F3-3: Double negation (NOT NOT A) evaluates to A" {
                $items = @(
                    [PSCustomObject]@{ Name = "target" }
                    [PSCustomObject]@{ Name = "other" }
                )
                $res = @($items | Find-ObjectByName "NOT NOT target")
                $res.Count | Should -Be 1
                $res[0].Name | Should -Be "target"
            }

            It "T2-F3-4: Idempotent AND conjunction (A AND A AND A) matches A" {
                $items = @(
                    [PSCustomObject]@{ Name = "target" }
                    [PSCustomObject]@{ Name = "other" }
                )
                $res = @($items | Find-ObjectByName "target AND target AND target")
                $res.Count | Should -Be 1
                $res[0].Name | Should -Be "target"
            }

            It "T2-F3-5: Idempotent OR disjunction (A OR A OR A) matches A" {
                $items = @(
                    [PSCustomObject]@{ Name = "target" }
                    [PSCustomObject]@{ Name = "other" }
                )
                $res = @($items | Find-ObjectByName "target OR target OR target")
                $res.Count | Should -Be 1
                $res[0].Name | Should -Be "target"
            }
        }

        # --- F4 Boundary ---
        Context "F4: Grouping Boundaries" {
            It "T2-F4-1: 5-level deeply nested parentheses evaluate accurately" {
                $items = @(
                    [PSCustomObject]@{ Name = "deep target" }
                    [PSCustomObject]@{ Name = "other" }
                )
                $res = @($items | Find-ObjectByName "(((((target)))))")
                $res.Count | Should -Be 1
                $res[0].Name | Should -Be "deep target"
            }

            It "T2-F4-2: Empty parentheses () throw syntax error" {
                $items = @([PSCustomObject]@{ Name = "test" })
                { @($items | Find-ObjectByName "apple AND ()") } | Should -Throw
            }

            It "T2-F4-3: Unclosed opening parenthesis throws syntax error" {
                $items = @([PSCustomObject]@{ Name = "test" })
                { @($items | Find-ObjectByName "(apple OR banana") } | Should -Throw
            }

            It "T2-F4-4: Stray closing parenthesis throws syntax error" {
                $items = @([PSCustomObject]@{ Name = "test" })
                { @($items | Find-ObjectByName "apple OR banana)") } | Should -Throw
            }

            It "T2-F4-5: Parentheses enclosing operator only throw syntax error" {
                $items = @([PSCustomObject]@{ Name = "test" })
                { @($items | Find-ObjectByName "apple AND (OR) banana") } | Should -Throw
            }
        }

        # --- F5 Boundary ---
        Context "F5: Unary NOT Boundaries" {
            It "T2-F5-1: Triple negation (NOT NOT NOT A) evaluates to NOT A" {
                $items = @(
                    [PSCustomObject]@{ Name = "match_me" }
                    [PSCustomObject]@{ Name = "exclude_me" }
                )
                $res = @($items | Find-ObjectByName "NOT NOT NOT exclude_me")
                $res.Count | Should -Be 1
                $res[0].Name | Should -Be "match_me"
            }

            It "T2-F5-2: Unary NOT on non-matching keyword matches all non-empty items" {
                $items = @(
                    [PSCustomObject]@{ Name = "alpha" }
                    [PSCustomObject]@{ Name = "beta" }
                )
                $res = @($items | Find-ObjectByName "NOT nonexistent")
                $res.Count | Should -Be 2
            }

            It "T2-F5-3: Trailing NOT without operand throws syntax error" {
                $items = @([PSCustomObject]@{ Name = "apple" })
                { @($items | Find-ObjectByName "apple NOT") } | Should -Throw
            }

            It "T2-F5-4: NOT against null property value skips null without throwing" {
                $items = @(
                    [PSCustomObject]@{ Name = $null }
                    [PSCustomObject]@{ Name = "valid" }
                )
                { $script:res = @($items | Find-ObjectByName "NOT test") } | Should -Not -Throw
                $script:res.Count | Should -Be 1
                $script:res[0].Name | Should -Be "valid"
            }

            It "T2-F5-5: NOT evaluating against whitespace-only target values" {
                $items = @(
                    [PSCustomObject]@{ Name = "   " }
                    [PSCustomObject]@{ Name = "content" }
                )
                $res = @($items | Find-ObjectByName "NOT target")
                $res.Count | Should -Be 1
                $res[0].Name | Should -Be "content"
            }
        }

        # --- F6 Boundary ---
        Context "F6: Dotted Property Path Boundaries" {
            It "T2-F6-1: 10-level deep property traversal" {
                $root = [PSCustomObject]@{ L1 = [PSCustomObject]@{ L2 = [PSCustomObject]@{ L3 = [PSCustomObject]@{ L4 = [PSCustomObject]@{ L5 = [PSCustomObject]@{ L6 = [PSCustomObject]@{ L7 = [PSCustomObject]@{ L8 = [PSCustomObject]@{ L9 = [PSCustomObject]@{ Leaf = "DeepMatch" } } } } } } } } } }
                $res = @($root | Find-ObjectByName "DeepMatch" -Property "L1.L2.L3.L4.L5.L6.L7.L8.L9.Leaf")
                $res.Count | Should -Be 1
            }

            It "T2-F6-2: Property path ending with dot handled gracefully" {
                $obj = [PSCustomObject]@{ Server = [PSCustomObject]@{ Name = "db1" } }
                { $res = @($obj | Find-ObjectByName "db1" -Property "Server.Name.") } | Should -Not -Throw
            }

            It "T2-F6-3: Property path starting with dot handled gracefully" {
                $obj = [PSCustomObject]@{ Server = [PSCustomObject]@{ Name = "db1" } }
                { $res = @($obj | Find-ObjectByName "db1" -Property ".Server.Name") } | Should -Not -Throw
            }

            It "T2-F6-4: Dotted path traversing into primitive type does not throw" {
                $obj = [PSCustomObject]@{ Count = 42 }
                { $script:res = @($obj | Find-ObjectByName "test" -Property "Count.NonExistent.Deep") } | Should -Not -Throw
                $script:res.Count | Should -Be 0
            }

            It "T2-F6-5: Dotted path on objects with special-character property names" {
                $obj = [PSCustomObject]@{
                    "@odata.context" = "https://example.com"
                    "meta.custom"    = "special_val"
                }
                $res = @($obj | Find-ObjectByName "special_val" -Property "meta.custom")
                $res.Count | Should -Be 1
            }
        }

        # --- F7 Boundary ---
        Context "F7: Wildcard Non-String Inspection Boundaries" {
            It "T2-F7-1: Object with 0 properties handled without throwing" {
                $emptyObj = [PSCustomObject]@{}
                { $script:res = @($emptyObj | Find-ObjectByName "anything" -Property *) } | Should -Not -Throw
                $script:res.Count | Should -Be 0
            }

            It "T2-F7-2: Object with all null properties handled without throwing" {
                $nullObj = [PSCustomObject]@{ P1 = $null; P2 = $null; P3 = $null }
                { $script:res = @($nullObj | Find-ObjectByName "anything" -Property *) } | Should -Not -Throw
                $script:res.Count | Should -Be 0
            }

            It "T2-F7-3: Object with 100 properties inspected accurately" {
                $hash = [ordered]@{}
                1..100 | ForEach-Object { $hash["Prop$_"] = "val$_" }
                $hash["TargetProp"] = "needle_in_haystack"
                $largeObj = [PSCustomObject]$hash

                $res = @($largeObj | Find-ObjectByName "needle_in_haystack" -Property *)
                $res.Count | Should -Be 1
            }

            It "T2-F7-4: Explicit boolean `$false` property inspected without dropping" {
                $obj = [PSCustomObject]@{ Name = "SecurityConfig"; Enforced = $false }
                $res = @($obj | Find-ObjectByName "False" -Property *)
                $res.Count | Should -Be 1
                $res[0].Name | Should -Be "SecurityConfig"
            }

            It "T2-F7-5: Numeric 0 property value inspected accurately" {
                $obj = [PSCustomObject]@{ Name = "Counter"; Retries = 0 }
                $res = @($obj | Find-ObjectByName "0" -Property * -Mode Exact)
                $res.Count | Should -Be 1
                $res[0].Name | Should -Be "Counter"
            }
        }

        # --- F8 Boundary ---
        Context "F8: Array Element Boundaries" {
            It "T2-F8-1: Empty array property handled cleanly" {
                $obj = [PSCustomObject]@{ Name = "Item"; Tags = @() }
                $res = @($obj | Find-ObjectByName "anything" -Property Tags)
                $res.Count | Should -Be 0
            }

            It "T2-F8-2: Single-element array property evaluated correctly" {
                $obj = [PSCustomObject]@{ Name = "Item"; Tags = @("single") }
                $res = @($obj | Find-ObjectByName "single" -Property Tags -Mode Exact)
                $res.Count | Should -Be 1
            }

            It "T2-F8-3: Array containing null elements skips nulls safely" {
                $obj = [PSCustomObject]@{ Name = "Item"; Tags = @($null, "valid", $null) }
                $res = @($obj | Find-ObjectByName "valid" -Property Tags -Mode Exact)
                $res.Count | Should -Be 1
            }

            It "T2-F8-4: Array containing nested arrays evaluated recursively or flattened" {
                $obj = [PSCustomObject]@{ Name = "Item"; Tags = @(@("inner1", "inner2"), "outer") }
                $res = @($obj | Find-ObjectByName "inner1" -Property Tags)
                $res.Count | Should -Be 1
            }

            It "T2-F8-5: Array containing empty strings handled safely" {
                $obj = [PSCustomObject]@{ Name = "Item"; Tags = @("", "  ", "actual") }
                $res = @($obj | Find-ObjectByName "actual" -Property Tags -Mode Exact)
                $res.Count | Should -Be 1
            }
        }

        # --- F9 Boundary ---
        Context "F9: Regex Resilience Boundaries" {
            It "T2-F9-1: Empty regex string in -Mode Regex handled cleanly" {
                $items = @([PSCustomObject]@{ Name = "anything" })
                { $res = @($items | Find-ObjectByName "" -Mode Regex) } | Should -Throw
            }

            It "T2-F9-2: Regex special characters in non-regex modes treated literally" {
                $items = @(
                    [PSCustomObject]@{ Name = "regex.*literal[test]" }
                    [PSCustomObject]@{ Name = "regex_other" }
                )
                $res = @($items | Find-ObjectByName ".*literal[test]" -Mode Contains)
                $res.Count | Should -Be 1
                $res[0].Name | Should -Be "regex.*literal[test]"
            }

            It "T2-F9-3: Regex lookahead and lookbehind expressions supported in Regex mode" {
                $items = @(
                    [PSCustomObject]@{ Name = "test123end" }
                    [PSCustomObject]@{ Name = "testABCend" }
                )
                $res = @($items | Find-ObjectByName '(?<=test)\d+(?=end)' -Mode Regex)
                $res.Count | Should -Be 1
                $res[0].Name | Should -Be "test123end"
            }

            It "T2-F9-4: Unicode escape sequences supported in Regex mode" {
                $items = @(
                    [PSCustomObject]@{ Name = "ABC" }
                    [PSCustomObject]@{ Name = "XYZ" }
                )
                $res = @($items | Find-ObjectByName '\u0041\u0042\u0043' -Mode Regex)
                $res.Count | Should -Be 1
                $res[0].Name | Should -Be "ABC"
            }

            It "T2-F9-5: Complex character class ranges evaluated accurately" {
                $items = @(
                    [PSCustomObject]@{ Name = "v1-prod" }
                    [PSCustomObject]@{ Name = "v9-test" }
                    [PSCustomObject]@{ Name = "va-prod" }
                )
                $res = @($items | Find-ObjectByName '^v[0-9]-prod$' -Mode Regex)
                $res.Count | Should -Be 1
                $res[0].Name | Should -Be "v1-prod"
            }
        }

        # --- F10 Boundary ---
        Context "F10: Clean Highlight Boundaries" {
            It "T2-F10-1: -Highlight on object with empty string property does not throw" {
                $obj = [PSCustomObject]@{ Name = "" }
                { $script:res = @($obj | Find-ObjectByName "test" -Highlight) } | Should -Not -Throw
                $script:res.Count | Should -Be 0
            }

            It "T2-F10-2: -Highlight on non-string property converted to string" {
                $obj = [PSCustomObject]@{ Name = "Svc"; Port = 8080 }
                { $script:res = @($obj | Find-ObjectByName "8080" -Property Port -Highlight) } | Should -Not -Throw
                $script:res.Count | Should -Be 1
            }

            It "T2-F10-3: -Highlight with regex meta-characters in Contains mode highlights safely" {
                $obj = [PSCustomObject]@{ Name = "config (v1.0)" }
                { $script:res = @($obj | Find-ObjectByName "(v1.0)" -Highlight) } | Should -Not -Throw
                $script:res.Count | Should -Be 1
            }

            It "T2-F10-4: -Highlight combined with -Count does not corrupt count output" {
                $items = @(
                    [PSCustomObject]@{ Name = "apple" }
                    [PSCustomObject]@{ Name = "apricot" }
                )
                $count = $items | Find-ObjectByName "ap" -Highlight -Count
                $count | Should -Be 2
                $count | Should -BeOfType [int]
            }

            It "T2-F10-5: -Highlight combined with -Quiet does not corrupt boolean output" {
                $items = @([PSCustomObject]@{ Name = "banana" })
                $quiet = $items | Find-ObjectByName "banana" -Highlight -Quiet
                $quiet | Should -Be $true
                $quiet | Should -BeOfType [bool]
            }
        }

        # --- F11 Boundary ---
        Context "F11: Intune Submodule Boundaries" {
            It "T2-F11-1: Idempotent re-import of FindObject.Intune does not throw" {
                if (-not (Test-Path $script:IntunePsm1)) {
                    Test-Path $script:IntunePsm1 | Should -BeTrue
                } else {
                    {
                        Import-Module $script:IntunePsm1 -Force
                        Import-Module $script:IntunePsm1 -Force
                    } | Should -Not -Throw
                }
            }

            It "T2-F11-2: Get-IntuneDevice rejects invalid Top range" {
                if (-not (Test-Path $script:IntunePsm1)) {
                    Test-Path $script:IntunePsm1 | Should -BeTrue
                } else {
                    Import-Module $script:IntunePsm1 -Force
                    { Get-IntuneDevice -Top 0 } | Should -Throw
                }
            }

            It "T2-F11-3: Disconnect-FindObjectGraph runs idempotently when already disconnected" {
                if (-not (Test-Path $script:IntunePsm1)) {
                    Test-Path $script:IntunePsm1 | Should -BeTrue
                } else {
                    Import-Module $script:IntunePsm1 -Force
                    { Disconnect-FindObjectGraph } | Should -Not -Throw
                }
            }

            It "T2-F11-4: Submodule cmdlets do not leak internal helper Invoke-FindObjectGraphRequest" {
                if (-not (Test-Path $script:IntuneManifest)) {
                    Test-Path $script:IntuneManifest | Should -BeTrue
                } else {
                    $manifest = Import-PowerShellDataFile $script:IntuneManifest
                    $manifest.FunctionsToExport | Should -Not -Contain "Invoke-FindObjectGraphRequest"
                }
            }

            It "T2-F11-5: Get-IntuneApp throws auth guard error when disconnected" {
                if (-not (Test-Path $script:IntunePsm1)) {
                    Test-Path $script:IntunePsm1 | Should -BeTrue
                } else {
                    Import-Module $script:IntunePsm1 -Force
                    Disconnect-FindObjectGraph -ErrorAction SilentlyContinue
                    { Get-IntuneApp } | Should -Throw "*Connect-FindObjectGraph*"
                }
            }
        }

        # --- F12 Boundary ---
        Context "F12: Core Module Isolation Boundaries" {
            It "T2-F12-1: Null pipeline input returns null without error" {
                { $script:res = $null | Find-ObjectByName "test" } | Should -Not -Throw
                $script:res | Should -BeNullOrEmpty
            }

            It "T2-F12-2: Set-FindObjectConfig rejects invalid Mode with validation error" {
                { Set-FindObjectConfig -Mode "NonExistentMode" } | Should -Throw
            }

            It "T2-F12-3: Empty SearchTerms string array throws parameter validation error" {
                $obj = [PSCustomObject]@{ Name = "test" }
                { @($obj | Find-ObjectByName -SearchTerms @()) } | Should -Throw
            }

            It "T2-F12-4: Core module does not export internal token or AST parsers" {
                $manifest = Import-PowerShellDataFile $script:CoreManifest
                $manifest.FunctionsToExport | Should -Not -Contain "ConvertTo-FindObjectTokens"
                $manifest.FunctionsToExport | Should -Not -Contain "ConvertTo-FindObjectAst"
            }

            It "T2-F12-5: Core module configuration retains and updates session state" {
                Set-FindObjectConfig -Mode Fuzzy | Out-Null
                (Get-FindObjectConfig).Mode | Should -Be "Fuzzy"
                Set-FindObjectConfig -Mode Contains | Out-Null
                (Get-FindObjectConfig).Mode | Should -Be "Contains"
            }
        }
    }

    # =========================================================================
    # TIER 3: CROSS-FEATURE COMBINATIONS (Pairwise & Multi-Feature Interactions)
    # =========================================================================
    Context "Tier 3: Cross-Feature Combinations" -Tags "Tier3" {

        It "T3-01: Quoted phrases inside parentheses with NOT (F1 + F3 + F4 + F5)" {
            $items = @(
                [PSCustomObject]@{ Name = "Visual Studio Community" }
                [PSCustomObject]@{ Name = "Visual Studio Code Insiders" }
                [PSCustomObject]@{ Name = "Visual Studio Code Stable" }
                [PSCustomObject]@{ Name = "Sublime Text" }
            )
            $res = @($items | Find-ObjectByName '("Visual Studio" OR "VS Code") AND NOT "Insiders"')
            $res.Count | Should -Be 2
            $names = $res | ForEach-Object { $_.Name }
            $names | Should -Contain "Visual Studio Community"
            $names | Should -Contain "Visual Studio Code Stable"
        }

        It "T3-02: Dotted property paths with quoted phrase and boolean AND (F1 + F4 + F6)" {
            $items = @(
                [PSCustomObject]@{ Meta = [PSCustomObject]@{ Category = "Machine Learning Core" } }
                [PSCustomObject]@{ Meta = [PSCustomObject]@{ Category = "Machine Learning Peripheral" } }
                [PSCustomObject]@{ Meta = [PSCustomObject]@{ Category = "Web Core" } }
            )
            $res = @($items | Find-ObjectByName '"Machine Learning" AND Core' -Property "Meta.Category")
            $res.Count | Should -Be 1
            $res[0].Meta.Category | Should -Be "Machine Learning Core"
        }

        It "T3-03: Array property evaluated in Exact mode with boolean AND (F2 + F3 + F8)" {
            $items = @(
                [PSCustomObject]@{ Name = "Srv1"; Roles = @("Domain Controller", "DNS Server") }
                [PSCustomObject]@{ Name = "Srv2"; Roles = @("Domain Controller", "File Server") }
                [PSCustomObject]@{ Name = "Srv3"; Roles = @("DNS Server") }
            )
            $res = @($items | Find-ObjectByName '"Domain Controller" AND "DNS Server"' -Property Roles -Mode Exact)
            $res.Count | Should -Be 1
            $res[0].Name | Should -Be "Srv1"
        }

        It "T3-04: Dotted path navigating into array of objects (F6 + F8)" {
            $items = @(
                [PSCustomObject]@{
                    Team = "Core"
                    Members = @(
                        [PSCustomObject]@{ Role = "Lead Developer" }
                        [PSCustomObject]@{ Role = "QA Specialist" }
                    )
                }
                [PSCustomObject]@{
                    Team = "Ops"
                    Members = @(
                        [PSCustomObject]@{ Role = "Site Reliability Engineer" }
                    )
                }
            )
            $res = @($items | Find-ObjectByName '"Site Reliability Engineer"' -Property "Members.Role" -Mode Exact)
            $res.Count | Should -Be 1
            $res[0].Team | Should -Be "Ops"
        }

        It "T3-05: Array property matching with Regex mode (F8 + F9)" {
            $items = @(
                [PSCustomObject]@{ Name = "ClusterA"; NodeIds = @("node-prod-001", "node-prod-002") }
                [PSCustomObject]@{ Name = "ClusterB"; NodeIds = @("node-dev-001") }
            )
            $res = @($items | Find-ObjectByName '^node-prod-\d{3}$' -Property NodeIds -Mode Regex)
            $res.Count | Should -Be 1
            $res[0].Name | Should -Be "ClusterA"
        }

        It "T3-06: Wildcard property inspection across nested objects and arrays (F6 + F7 + F8)" {
            $items = @(
                [PSCustomObject]@{
                    Id = 501
                    Tags = @("Critical", "Audit")
                    Details = [PSCustomObject]@{ Region = "us-east-1" }
                }
                [PSCustomObject]@{
                    Id = 502
                    Tags = @("Low")
                    Details = [PSCustomObject]@{ Region = "eu-west-1" }
                }
            )
            $res = @($items | Find-ObjectByName "501" -Property *)
            $res.Count | Should -Be 1
            $res[0].Id | Should -Be 501
        }

        It "T3-07: Highlighting combined with quoted phrases and boolean OR (F1 + F10)" {
            $items = @(
                [PSCustomObject]@{ Name = "Windows Server 2022" }
                [PSCustomObject]@{ Name = "Ubuntu Linux 24.04" }
                [PSCustomObject]@{ Name = "Red Hat Enterprise" }
            )
            $res = @($items | Find-ObjectByName '"Windows Server" OR "Ubuntu Linux"' -Highlight)
            $res.Count | Should -Be 2
            $esc = [char]27
            $res[0].Name | Should -Match ([regex]::Escape("${esc}[1;33m"))
            $res[1].Name | Should -Match ([regex]::Escape("${esc}[1;33m"))
        }

        It "T3-08: Unary NOT combined with dotted property path (F5 + F6)" {
            $items = @(
                [PSCustomObject]@{ Account = [PSCustomObject]@{ Status = "Active" }; User = "user1" }
                [PSCustomObject]@{ Account = [PSCustomObject]@{ Status = "Disabled" }; User = "user2" }
            )
            $res = @($items | Find-ObjectByName "NOT Disabled" -Property "Account.Status")
            $res.Count | Should -Be 1
            $res[0].User | Should -Be "user1"
        }

        It "T3-09: Regex mode with unary NOT and parentheses: NOT (^[0-9]+$) (F4 + F5 + F9)" {
            $items = @(
                [PSCustomObject]@{ Code = "12345" }
                [PSCustomObject]@{ Code = "ABCDE" }
                [PSCustomObject]@{ Code = "99999" }
            )
            $res = @($items | Find-ObjectByName "NOT (^[0-9]+$)" -Property Code -Mode Regex)
            $res.Count | Should -Be 1
            $res[0].Code | Should -Be "ABCDE"
        }

        It "T3-10: Wildcard non-string search with Boolean precedence: (100 OR 200) AND NOT 500 (F3 + F4 + F7)" {
            $items = @(
                [PSCustomObject]@{ Name = "A"; Code = 100; Error = 0 }
                [PSCustomObject]@{ Name = "B"; Code = 200; Error = 500 }
                [PSCustomObject]@{ Name = "C"; Code = 300; Error = 0 }
            )
            $res = @($items | Find-ObjectByName "(100 OR 200) AND NOT 500" -Property *)
            $res.Count | Should -Be 1
            $res[0].Name | Should -Be "A"
        }

        It "T3-11: Array property with Prefix mode and parentheses (F4 + F5 + F8)" {
            $items = @(
                [PSCustomObject]@{ Name = "App1"; Environments = @("development", "testing") }
                [PSCustomObject]@{ Name = "App2"; Environments = @("production", "staging") }
                [PSCustomObject]@{ Name = "App3"; Environments = @("development", "production") }
            )
            $res = @($items | Find-ObjectByName "(dev OR test) AND NOT prod" -Property Environments -Mode StartsWith)
            $res.Count | Should -Be 1
            $res[0].Name | Should -Be "App1"
        }

        It "T3-12: Case-sensitive matching with quoted phrases and boolean logic (F1 + F2 + F5)" {
            $items = @(
                [PSCustomObject]@{ Name = "API Gateway Core" }
                [PSCustomObject]@{ Name = "api gateway core" }
                [PSCustomObject]@{ Name = "API Gateway Internal" }
            )
            $res = @($items | Find-ObjectByName '"API Gateway" AND NOT Internal' -CaseSensitive)
            $res.Count | Should -Be 1
            $res[0].Name | Should -Be "API Gateway Core"
        }

        It "T3-13: Result limiting (-First, -Skip) with boolean precedence and dotted properties (F3 + F6)" {
            $items = 1..20 | ForEach-Object {
                [PSCustomObject]@{
                    Meta = [PSCustomObject]@{
                        Env = if ($_ % 2 -eq 0) { "Production" } else { "Development" }
                        Tier = if ($_ -gt 10) { "Gold" } else { "Silver" }
                    }
                    Index = $_
                }
            }
            # Production AND Gold -> Even numbers > 10: 12, 14, 16, 18, 20 (5 items)
            $res = @($items | Find-ObjectByName "Production AND Gold" -Property "Meta.Env" -Skip 2 -First 2)
            # Dotted search across Meta
            $resAll = @($items | Find-ObjectByName "Production" -Property "Meta.Env" -Skip 2 -First 2)
            $resAll.Count | Should -Be 2
            $resAll[0].Index | Should -Be 6
            $resAll[1].Index | Should -Be 8
        }

        It "T3-14: Count and Quiet switches with quoted phrases and array properties (F1 + F8)" {
            $items = @(
                [PSCustomObject]@{ Name = "App1"; Tags = @("Cloud Native", "Kubernetes") }
                [PSCustomObject]@{ Name = "App2"; Tags = @("Legacy Monolith") }
            )
            $count = $items | Find-ObjectByName '"Cloud Native"' -Property Tags -Count
            $count | Should -Be 1

            $quiet = $items | Find-ObjectByName '"Cloud Native"' -Property Tags -Quiet
            $quiet | Should -Be $true
        }

        It "T3-15: Chained pipeline filtering through fob twice (Composition)" {
            $items = @(
                [PSCustomObject]@{ Department = "Security"; Title = "Senior Analyst" }
                [PSCustomObject]@{ Department = "Security"; Title = "Junior Analyst" }
                [PSCustomObject]@{ Department = "Sales"; Title = "Senior Executive" }
            )
            $res = @($items | fob "Security" -Property Department | fob "Senior" -Property Title)
            $res.Count | Should -Be 1
            $res[0].Title | Should -Be "Senior Analyst"
        }

        It "T3-16: Dotted property resolution with -AsString parameter fallback" {
            $strings = @("Server.Production.Primary", "Server.Development.Secondary")
            $res = @($strings | Find-ObjectByName "Production" -AsString)
            $res.Count | Should -Be 1
            $res[0] | Should -Be "Server.Production.Primary"
        }

        It "T3-17: Fuzzy mode with -First 1 early termination" {
            $items = @(
                [PSCustomObject]@{ Name = "FindObject.psm1" }
                [PSCustomObject]@{ Name = "FindObject.psd1" }
                [PSCustomObject]@{ Name = "FindObject.Tests.ps1" }
            )
            $res = @($items | Find-ObjectByName "fndobj" -Mode Fuzzy -First 1)
            $res.Count | Should -Be 1
            $res[0].Name | Should -Be "FindObject.psm1"
        }

        It "T3-18: StartsWith mode with array property and boolean OR" {
            $items = @(
                [PSCustomObject]@{ Name = "Tool1"; Prefixes = @("aws-cli", "az-cli") }
                [PSCustomObject]@{ Name = "Tool2"; Prefixes = @("gcloud", "oci") }
            )
            $res = @($items | Find-ObjectByName "aws OR gcloud" -Property Prefixes -Mode StartsWith)
            $res.Count | Should -Be 2
        }

        It "T3-19: Unary NOT with -Property * on heterogeneous PSCustomObject" {
            $items = @(
                [PSCustomObject]@{ Name = "Node1"; IP = "10.0.0.1"; Status = "Error" }
                [PSCustomObject]@{ Name = "Node2"; IP = "10.0.0.2"; Status = "OK" }
            )
            $res = @($items | Find-ObjectByName "NOT Error" -Property *)
            $res.Count | Should -Be 1
            $res[0].Name | Should -Be "Node2"
        }

        It 'T3-20: Parentheses with nested NOT and quoted phrases: NOT ("legacy app" OR "deprecated api")' {
            $items = @(
                [PSCustomObject]@{ Name = "modern service" }
                [PSCustomObject]@{ Name = "legacy app v1" }
                [PSCustomObject]@{ Name = "deprecated api service" }
            )
            $res = @($items | Find-ObjectByName 'NOT ("legacy app" OR "deprecated api")')
            $res.Count | Should -Be 1
            $res[0].Name | Should -Be "modern service"
        }

        It "T3-21: Multi-level dotted path with integer leaf value" {
            $items = @(
                [PSCustomObject]@{ Cluster = [PSCustomObject]@{ Spec = [PSCustomObject]@{ Replicas = 3 } } }
                [PSCustomObject]@{ Cluster = [PSCustomObject]@{ Spec = [PSCustomObject]@{ Replicas = 10 } } }
            )
            $res = @($items | Find-ObjectByName "10" -Property "Cluster.Spec.Replicas")
            $res.Count | Should -Be 1
            $res[0].Cluster.Spec.Replicas | Should -Be 10
        }

        It "T3-22: Array property containing dates evaluated with StartsWith" {
            $items = @(
                [PSCustomObject]@{ Name = "Batch1"; AuditDates = @("2026-01-01", "2026-02-01") }
                [PSCustomObject]@{ Name = "Batch2"; AuditDates = @("2025-12-01") }
            )
            $res = @($items | Find-ObjectByName "2026" -Property AuditDates -Mode StartsWith)
            $res.Count | Should -Be 1
            $res[0].Name | Should -Be "Batch1"
        }

        It "T3-23: Highlighting multiple quoted phrases across multiple objects" {
            $items = @(
                [PSCustomObject]@{ Description = "Setup Windows Server now" }
                [PSCustomObject]@{ Description = "Install Red Hat now" }
            )
            $res = @($items | Find-ObjectByName '"Windows Server" OR "Red Hat"' -Property Description -Highlight)
            $res.Count | Should -Be 2
        }

        It "T3-24: Chained pipeline resilience: first fob succeeds, second malformed regex halts cleanly" {
            $items = @([PSCustomObject]@{ Name = "valid" })
            { @($items | fob "valid" | fob "[" -Mode Regex) } | Should -Throw
        }

        It "T3-25: Core module configuration overriding Mode while filtering dotted array properties" {
            Set-FindObjectConfig -Mode Exact | Out-Null
            $items = @(
                [PSCustomObject]@{ Config = [PSCustomObject]@{ Tags = @("audit", "prod") } }
                [PSCustomObject]@{ Config = [PSCustomObject]@{ Tags = @("auditing", "dev") } }
            )
            # Default mode is now Exact
            $res = @($items | Find-ObjectByName "audit" -Property "Config.Tags")
            $res.Count | Should -Be 1
        }
    }

    # =========================================================================
    # TIER 4: REAL-WORLD APPLICATION SCENARIOS
    # =========================================================================
    Context "Tier 4: Real-World Application Scenarios" -Tags "Tier4" {

        # Scenario 1: Windows Process Filtering & Triage
        Context "Scenario 1: Windows Process Triage" {
            BeforeAll {
                $script:ProcessData = @(
                    [PSCustomObject]@{ Name = "chrome"; Id = 1042; WorkingSet = 120450000; Path = "C:\Program Files\Google\Chrome\chrome.exe"; CommandLine = "--type=normal" }
                    [PSCustomObject]@{ Name = "chrome"; Id = 1044; WorkingSet = 45200000;  Path = "C:\Program Files\Google\Chrome\chrome.exe"; CommandLine = "--type=renderer --extension" }
                    [PSCustomObject]@{ Name = "chrome"; Id = 1046; WorkingSet = 32100000;  Path = "C:\Program Files\Google\Chrome\chrome.exe"; CommandLine = "--type=crashpad-handler" }
                    [PSCustomObject]@{ Name = "msedge"; Id = 2012; WorkingSet = 110500000; Path = "C:\Program Files (x86)\Microsoft\Edge\msedge.exe"; CommandLine = "--type=normal" }
                    [PSCustomObject]@{ Name = "svchost"; Id = 890; WorkingSet = 15400000;  Path = "C:\Windows\System32\svchost.exe"; CommandLine = "-k DcomLaunch" }
                    [PSCustomObject]@{ Name = "node";   Id = 5540; WorkingSet = 210000000; Path = "C:\Program Files\nodejs\node.exe"; CommandLine = "server.js --inspect=9229" }
                )
            }

            It "T4-01: Filter primary browser processes excluding background crash handlers" {
                $res = @($script:ProcessData | Find-ObjectByName "(chrome OR msedge) AND NOT crashpad" -Property *)
                $res.Count | Should -Be 3
                $ids = $res | ForEach-Object { $_.Id }
                $ids | Should -Not -Contain 1046
            }

            It "T4-02: Locate developer processes with inspect port enabled" {
                $res = @($script:ProcessData | Find-ObjectByName '"node.exe" AND "--inspect"' -Property *)
                $res.Count | Should -Be 1
                $res[0].Name | Should -Be "node"
            }

            It "T4-03: Process paging with -First and -Skip on high-cardinality workloads" {
                $res = @($script:ProcessData | Find-ObjectByName "chrome" -Skip 1 -First 2)
                $res.Count | Should -Be 2
                $res[0].Id | Should -Be 1044
                $res[1].Id | Should -Be 1046
            }

            It "T4-04: Fast existence check with -Quiet for active service host" {
                $exists = $script:ProcessData | Find-ObjectByName "svchost" -Quiet
                $exists | Should -Be $true
            }
        }

        # Scenario 2: Windows Service Audit & Security Hardening
        Context "Scenario 2: Windows Service Audit & Security Hardening" {
            BeforeAll {
                $script:ServiceData = @(
                    [PSCustomObject]@{ Name = "WinDefend"; DisplayName = "Microsoft Defender Antivirus Service"; Status = "Running"; StartType = "Automatic"; PathName = "C:\ProgramData\Microsoft\Windows Defender\Platform\MsMpEng.exe"; ServiceAccount = "LocalSystem" }
                    [PSCustomObject]@{ Name = "MpsSvc"; DisplayName = "Windows Defender Firewall"; Status = "Running"; StartType = "Automatic"; PathName = "C:\Windows\System32\svchost.exe -k LocalServiceNoNetwork"; ServiceAccount = "NT AUTHORITY\LocalService" }
                    [PSCustomObject]@{ Name = "DiagTrack"; DisplayName = "Connected User Experiences and Telemetry"; Status = "Stopped"; StartType = "Disabled"; PathName = "C:\Windows\System32\svchost.exe -k utcsvc"; ServiceAccount = "NT AUTHORITY\LocalService" }
                    [PSCustomObject]@{ Name = "VulnerableApp"; DisplayName = "Legacy Backup Agent"; Status = "Running"; StartType = "Automatic"; PathName = "C:\Program Files\Vulnerable App\agent.exe"; ServiceAccount = "NT AUTHORITY\LocalService" }
                    [PSCustomObject]@{ Name = "UnquotedSvc"; DisplayName = "Custom Monitoring Daemon"; Status = "Running"; StartType = "Automatic"; PathName = "C:\Program Files\Custom Daemon\daemon.exe"; ServiceAccount = "corp\svc_monitor" }
                )
            }

            It "T4-05: Audit active security services (Defender OR Firewall) AND Running" {
                $res = @($script:ServiceData | Find-ObjectByName "(Defender OR Firewall) AND Running" -Property *)
                $res.Count | Should -Be 2
                $names = $res | ForEach-Object { $_.Name }
                $names | Should -Contain "WinDefend"
                $names | Should -Contain "MpsSvc"
            }

            It "T4-06: Locate services running under non-standard custom service accounts" {
                $res = @($script:ServiceData | Find-ObjectByName 'NOT "LocalSystem" AND NOT "NT AUTHORITY"' -Property ServiceAccount)
                $res.Count | Should -Be 1
                $res[0].Name | Should -Be "UnquotedSvc"
            }

            It "T4-07: Detect unquoted service paths containing spaces via Regex mode" {
                # Unquoted path: starts with C:\, contains space before .exe, does not start with quote
                $res = @($script:ServiceData | Find-ObjectByName '^[A-Za-z]:\\[^"]*\s[^"]*\.exe' -Property PathName -Mode Regex)
                $res.Count | Should -Be 3
                $names = $res | ForEach-Object { $_.Name }
                $names | Should -Contain "WinDefend"
                $names | Should -Contain "VulnerableApp"
                $names | Should -Contain "UnquotedSvc"
            }

            It "T4-08: Filter telemetry and diagnostic services with disabled status" {
                $res = @($script:ServiceData | Find-ObjectByName "(Telemetry OR Diag) AND Disabled" -Property *)
                $res.Count | Should -Be 1
                $res[0].Name | Should -Be "DiagTrack"
            }
        }

        # Scenario 3: Active Directory / Entra ID User Auditing
        Context "Scenario 3: Active Directory / Entra ID User Auditing" {
            BeforeAll {
                $script:UserData = @(
                    [PSCustomObject]@{
                        SamAccountName = "jdoe"
                        UserPrincipalName = "jdoe@contoso.com"
                        Department = "IT Infrastructure"
                        Enabled = $true
                        Manager = [PSCustomObject]@{ DisplayName = "Alice Smith"; Email = "asmith@contoso.com" }
                        MemberOf = @("CN=Domain Admins,OU=Groups,DC=contoso,DC=com", "CN=VPN Users,OU=Groups,DC=contoso,DC=com")
                    }
                    [PSCustomObject]@{
                        SamAccountName = "bg_admin"
                        UserPrincipalName = "bg_admin@contoso.com"
                        Department = "Security Operations"
                        Enabled = $true
                        Manager = [PSCustomObject]@{ DisplayName = "Alice Smith"; Email = "asmith@contoso.com" }
                        MemberOf = @("CN=Domain Admins,OU=Groups,DC=contoso,DC=com", "CN=BreakGlass,OU=Groups,DC=contoso,DC=com")
                    }
                    [PSCustomObject]@{
                        SamAccountName = "ext_contractor"
                        UserPrincipalName = "ext_contractor@contractor.contoso.com"
                        Department = "Software Engineering"
                        Enabled = $false
                        Manager = [PSCustomObject]@{ DisplayName = "Bob Jones"; Email = "bjones@contoso.com" }
                        MemberOf = @("CN=Developers,OU=Groups,DC=contoso,DC=com")
                    }
                )
            }

            It "T4-09: Triage Domain Admins excluding emergency BreakGlass accounts" {
                $res = @($script:UserData | Find-ObjectByName '"Domain Admins" AND NOT BreakGlass' -Property MemberOf)
                $res.Count | Should -Be 1
                $res[0].SamAccountName | Should -Be "jdoe"
            }

            It "T4-10: Audit users reporting to specific manager via dotted property" {
                $res = @($script:UserData | Find-ObjectByName '"Alice Smith"' -Property "Manager.DisplayName")
                $res.Count | Should -Be 2
                $names = $res | ForEach-Object { $_.SamAccountName }
                $names | Should -Contain "jdoe"
                $names | Should -Contain "bg_admin"
            }

            It "T4-11: Detect disabled contractor accounts" {
                $res = @($script:UserData | Find-ObjectByName "contractor AND False" -Property *)
                $res.Count | Should -Be 1
                $res[0].SamAccountName | Should -Be "ext_contractor"
            }

            It "T4-12: Total count of active staff in IT or Security departments" {
                $count = $script:UserData | Find-ObjectByName "(Infrastructure OR Security) AND True" -Property * -Count
                $count | Should -Be 2
            }
        }

        # Scenario 4: Intune Device & Compliance Inventory
        Context "Scenario 4: Intune Device & Compliance Inventory" {
            BeforeAll {
                $script:DeviceData = @(
                    [PSCustomObject]@{
                        id = "dev-001"
                        deviceName = "TONY-WIN11-PRO"
                        operatingSystem = "Windows"
                        osVersion = "10.0.22631.3007"
                        complianceState = "Compliant"
                        hardwareInformation = [PSCustomObject]@{ totalStorageSpace = 1000204886016 }
                        configurationProfiles = @("BitLocker Base", "WiFi Enterprise", "Defender EDR")
                    }
                    [PSCustomObject]@{
                        id = "dev-002"
                        deviceName = "TONY-MACBOOK-AIR"
                        operatingSystem = "macOS"
                        osVersion = "14.4.1"
                        complianceState = "NonCompliant"
                        hardwareInformation = [PSCustomObject]@{ totalStorageSpace = 500102443008 }
                        configurationProfiles = @("FileVault Base", "WiFi Enterprise")
                    }
                    [PSCustomObject]@{
                        id = "dev-003"
                        deviceName = "SALES-WIN10-LTP"
                        operatingSystem = "Windows"
                        osVersion = "10.0.19045.4046"
                        complianceState = "NonCompliant"
                        hardwareInformation = [PSCustomObject]@{ totalStorageSpace = 256000000000 }
                        configurationProfiles = @("BitLocker Base")
                    }
                    [PSCustomObject]@{
                        id = "dev-004"
                        deviceName = "EXEC-IPAD-PRO"
                        operatingSystem = "iOS"
                        osVersion = "17.4.1"
                        complianceState = "Compliant"
                        hardwareInformation = [PSCustomObject]@{ totalStorageSpace = 128000000000 }
                        configurationProfiles = @("AirWatch MDM")
                    }
                )
            }

            It "T4-13: Identify Non-Compliant enterprise laptops: (Windows OR macOS) AND NonCompliant" {
                $res = @($script:DeviceData | Find-ObjectByName "(Windows OR macOS) AND NonCompliant" -Property *)
                $res.Count | Should -Be 2
                $names = $res | ForEach-Object { $_.deviceName }
                $names | Should -Contain "TONY-MACBOOK-AIR"
                $names | Should -Contain "SALES-WIN10-LTP"
            }

            It "T4-14: Audit devices with missing Defender EDR profile using array evaluation" {
                $res = @($script:DeviceData | Find-ObjectByName "Windows AND NOT Defender" -Property *)
                $res.Count | Should -Be 1
                $res[0].deviceName | Should -Be "SALES-WIN10-LTP"
            }

            It "T4-15: Query storage capacity via dotted hardware path" {
                $res = @($script:DeviceData | Find-ObjectByName "1000204886016" -Property "hardwareInformation.totalStorageSpace" -Mode Exact)
                $res.Count | Should -Be 1
                $res[0].deviceName | Should -Be "TONY-WIN11-PRO"
            }

            It "T4-16: Fast existence test for iOS mobile devices" {
                $hasIos = $script:DeviceData | Find-ObjectByName "iOS" -Property operatingSystem -Quiet
                $hasIos | Should -Be $true
            }
        }

        # Scenario 5: Web Server Access Log Inspection
        Context "Scenario 5: Web Server Access Log Inspection" {
            BeforeAll {
                $script:LogData = @(
                    [PSCustomObject]@{ ClientIP = "192.168.1.100"; Method = "GET";  UriStem = "/index.html"; StatusCode = 200; UserAgent = "Mozilla/5.0 Chrome/120.0" }
                    [PSCustomObject]@{ ClientIP = "10.0.0.50";     Method = "POST"; UriStem = "/api/v2/checkout"; StatusCode = 500; UserAgent = "ShopMobile/1.2" }
                    [PSCustomObject]@{ ClientIP = "10.0.0.51";     Method = "POST"; UriStem = "/api/v2/checkout"; StatusCode = 503; UserAgent = "ShopMobile/1.2" }
                    [PSCustomObject]@{ ClientIP = "192.168.1.101"; Method = "GET";  UriStem = "/healthz"; StatusCode = 500; UserAgent = "KubeletHealthCheck" }
                    [PSCustomObject]@{ ClientIP = "45.33.32.156";  Method = "GET";  UriStem = "/wp-login.php"; StatusCode = 404; UserAgent = "sqlmap/1.6.12#stable" }
                )
            }

            It "T4-17: Detect critical 5xx server errors excluding health checks" {
                $res = @($script:LogData | Find-ObjectByName "(500 OR 503) AND NOT healthz" -Property *)
                $res.Count | Should -Be 2
                $ips = $res | ForEach-Object { $_.ClientIP }
                $ips | Should -Contain "10.0.0.50"
                $ips | Should -Contain "10.0.0.51"
            }

            It "T4-18: Locate security penetration scanning user agents" {
                $res = @($script:LogData | Find-ObjectByName '"sqlmap" OR "nikto" OR "nmap"' -Property UserAgent)
                $res.Count | Should -Be 1
                $res[0].ClientIP | Should -Be "45.33.32.156"
            }

            It "T4-19: Triage API v2 POST operations" {
                $res = @($script:LogData | Find-ObjectByName '"/api/v2/" AND POST' -Property *)
                $res.Count | Should -Be 2
            }

            It "T4-20: Count requests returning HTTP 200 status code" {
                $count = $script:LogData | Find-ObjectByName "200" -Property StatusCode -Mode Exact -Count
                $count | Should -Be 1
            }
        }

        # Scenario 6: CI/CD Software Bill-of-Materials & Vulnerability Audit
        Context "Scenario 6: CI/CD Software Bill-of-Materials & Vulnerability Audit" {
            BeforeAll {
                $script:SbomData = @(
                    [PSCustomObject]@{
                        Package = "System.Text.Json"
                        Version = "8.0.0"
                        License = "MIT"
                        Vulnerabilities = @("CVE-2024-21907:HIGH")
                    }
                    [PSCustomObject]@{
                        Package = "log4j-core"
                        Version = "2.14.1"
                        License = "Apache-2.0"
                        Vulnerabilities = @("CVE-2021-44228:CRITICAL", "CVE-2021-45046:CRITICAL")
                    }
                    [PSCustomObject]@{
                        Package = "legacy-crypto"
                        Version = "1.0.2"
                        License = "GPL-3.0"
                        Vulnerabilities = @("CVE-2026-1101:CRITICAL:Mitigated")
                    }
                    [PSCustomObject]@{
                        Package = "pester"
                        Version = "5.6.1"
                        License = "Apache-2.0"
                        Vulnerabilities = @()
                    }
                )
            }

            It "T4-21: Audit unmitigated CRITICAL vulnerabilities in dependency tree" {
                $res = @($script:SbomData | Find-ObjectByName "CRITICAL AND NOT Mitigated" -Property Vulnerabilities)
                $res.Count | Should -Be 1
                $res[0].Package | Should -Be "log4j-core"
            }

            It "T4-22: Filter restrictive copyleft licenses: (GPL OR AGPL) AND NOT MIT" {
                $res = @($script:SbomData | Find-ObjectByName "(GPL OR AGPL) AND NOT MIT" -Property License)
                $res.Count | Should -Be 1
                $res[0].Package | Should -Be "legacy-crypto"
            }

            It "T4-23: Detect packages with zero known vulnerabilities" {
                $res = @($script:SbomData | Find-ObjectByName "NOT CVE" -Property Vulnerabilities)
                $res.Count | Should -Be 1
                $res[0].Package | Should -Be "pester"
            }

            It "T4-24: Identify modern 2026 CVE vulnerabilities" {
                $res = @($script:SbomData | Find-ObjectByName '"CVE-2026-"' -Property Vulnerabilities)
                $res.Count | Should -Be 1
                $res[0].Package | Should -Be "legacy-crypto"
            }
        }
    }
}
