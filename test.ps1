
$modulePath = Join-Path $PSScriptRoot "FindObject.psm1"
Import-Module $modulePath -Force

function Assert-Equal {
    param($Expected, $Actual, $Message)
    if ($Expected -eq $Actual) {
        Write-Host "PASS: $Message" -ForegroundColor Green
    } else {
        Write-Host "FAIL: $Message. Expected '$Expected', but got '$Actual'" -ForegroundColor Red
        exit 1
    }
}

function Assert-Contains {
    param($Collection, $Item, $Message)
    if ($Collection -contains $Item) {
        Write-Host "PASS: $Message" -ForegroundColor Green
    } else {
        Write-Host "FAIL: $Message. Collection did not contain '$Item'" -ForegroundColor Red
        exit 1
    }
}

# Test 1: Single keyword
$obj = [PSCustomObject]@{ Name = "testObject" }
$res = $obj | Find-ObjectByName -SearchTerms "test"
Assert-Equal $obj $res "Single keyword match"

# Test 2: OR logic (default)
$obj1 = [PSCustomObject]@{ Name = "apple" }
$obj2 = [PSCustomObject]@{ Name = "banana" }
$obj3 = [PSCustomObject]@{ Name = "cherry" }
$list = $obj1, $obj2, $obj3
$res = $list | Find-ObjectByName -SearchTerms "apple", "cherry"
Assert-Equal 2 $res.Count "OR logic count"
Assert-Contains $res $obj1 "Found apple"
Assert-Contains $res $obj3 "Found cherry"

# Test 3: AND logic
$obj1 = [PSCustomObject]@{ Name = "apple pie" }
$obj2 = [PSCustomObject]@{ Name = "apple tart" }
$obj3 = [PSCustomObject]@{ Name = "cherry pie" }
$list = $obj1, $obj2, $obj3
$res = $list | Find-ObjectByName -SearchTerms "apple", "and", "pie"
Assert-Equal 1 $res.Count "AND logic count"
Assert-Contains $res $obj1 "Found apple pie"

# Test 4: OR logic with explicit operator
$res = $list | Find-ObjectByName -SearchTerms "apple", "or", "cherry"
Assert-Equal 3 $res.Count "Explicit OR logic count"

# Test 5: Empty/Null handling
$res = $null | Find-ObjectByName -SearchTerms "test"
Assert-Equal $null $res "Null input handled"

Write-Host "All tests passed!"
