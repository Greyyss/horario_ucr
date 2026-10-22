$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
if (-not (Test-Path -LiteralPath 'pubspec.yaml')) {
  throw 'Extrae este paquete en la raiz del proyecto, junto a lib y pubspec.yaml.'
}
$flutterTool = Get-Command flutter.bat -ErrorAction SilentlyContinue
if (-not $flutterTool) { throw 'Flutter no esta disponible en PATH. Usa la terminal donde ejecutas flutter analyze.' }
New-Item -ItemType Directory -Force 'test-results' | Out-Null
$eventsPath = Join-Path $PSScriptRoot 'test-results\formulario-events.jsonl'
$resultsPath = Join-Path $PSScriptRoot 'test-results\formulario-results.json'
Write-Host 'Probando el formulario de nombramientos. No se usa Firebase.'
& $flutterTool.Source test --no-pub --machine test/appointment_form_test.dart | Tee-Object -FilePath $eventsPath
$testExit = $LASTEXITCODE
$names = @{}
$tests = @()
$errors = @()
foreach ($line in Get-Content -LiteralPath $eventsPath) {
  try { $event = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
  if ($event.type -eq 'testStart') { $names[$event.test.id] = $event.test.name }
  if ($event.type -eq 'error') { $errors += [pscustomobject]@{testID=$event.testID; error=$event.error; stackTrace=$event.stackTrace} }
  if ($event.type -eq 'testDone' -and -not $event.hidden -and $names.ContainsKey($event.testID)) {
    $name = $names[$event.testID]
    if ($name -notlike 'loading *') {
      $tests += [pscustomobject]@{name=$name; result=$event.result; skipped=[bool]$event.skipped; errors=@($errors | Where-Object {$_.testID -eq $event.testID})}
    }
  }
}
$passed = @($tests | Where-Object {$_.result -eq 'success' -and -not $_.skipped}).Count
$failed = @($tests | Where-Object {$_.result -ne 'success' -and -not $_.skipped}).Count
[pscustomobject]@{
  generatedAt=(Get-Date).ToUniversalTime().ToString('o')
  exitCode=$testExit
  passed=$passed
  failed=$failed
  tests=$tests
} | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultsPath -Encoding utf8
Write-Host "Resultado: $passed aprobadas, $failed fallidas. Codigo de salida: $testExit"
Write-Host "Informe: $resultsPath"
if ($testExit -ne 0) { Write-Host 'Hay fallos o un error del ejecutor. Comparte el informe y las ultimas lineas.' -ForegroundColor Yellow; exit $testExit }

