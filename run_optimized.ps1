Import-Module ./FindObject_Optimized.psm1 -Force
$objects = 1..10000 | ForEach-Object { [PSCustomObject]@{ Name = "testObject$_" } }
Measure-Command { $objects | Find-ObjectByName -SearchTerms "testObject" }
Measure-Command { $objects | Find-ObjectByName -SearchTerms "testObject", "test" }
Measure-Command { $objects | Find-ObjectByName -SearchTerms "testObject", "and", "test" }
