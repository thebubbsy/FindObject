Import-Module ./FindObject.psm1 -Force
$items = 1..10000 | ForEach-Object { [PSCustomObject]@{ Name = "testObject$_" } }
$timeBefore = Measure-Command {
    $items | Find-ObjectByName "testObject500", "or", "testObject9000" | Out-Null
}
$timeBefore.TotalMilliseconds
