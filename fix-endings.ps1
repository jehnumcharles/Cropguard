$content = Get-Content "contracts\policy-bundling.clar" -Raw
$content = $content -replace "`r`n", "`n"
$content = $content -replace "`r", "`n"
[System.IO.File]::WriteAllText("contracts\policy-bundling.clar", $content, [System.Text.UTF8Encoding]::new($false))
Write-Host "Line endings fixed!"
