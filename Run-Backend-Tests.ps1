$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
New-Item -ItemType Directory -Force (Join-Path $PSScriptRoot 'test-results') | Out-Null
$javaCandidates = @(
  'C:\Program Files\Java\jdk-21\bin\java.exe',
  'C:\Program Files\Java\jdk-24\bin\java.exe'
)
$javaRuntime = $javaCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
$cachedBase = 'C:\Users\lg809\Documents\Codex\2026-10-17\new-chat-4\work\storage-prep'
$emulatorJar = Join-Path $cachedBase 'emulators\cloud-firestore-emulator-v1.22.0.jar'
$cachedModules = Join-Path $cachedBase 'project\node_modules'
$oldNodePath = $env:NODE_PATH
$oldEmulatorHost = $env:FIRESTORE_EMULATOR_HOST
$emulatorProcess = $null

try {
  if (-not $javaRuntime -or -not (Test-Path -LiteralPath $emulatorJar)) {
    throw 'No se encontro Java 21+ o el emulador instalado. Comparte este error para adaptar las rutas del equipo.'
  }
  if (-not (Test-Path -LiteralPath (Join-Path $cachedModules '@firebase\rules-unit-testing'))) {
    throw 'No se encontraron las dependencias locales. Comparte este error para adaptar las rutas del equipo.'
  }
  $existingListener = Get-NetTCPConnection -LocalPort 8186 -State Listen -ErrorAction SilentlyContinue
  if ($existingListener) { throw 'El puerto 8186 ya esta ocupado. Cierra ese emulador antes de continuar.' }
    $projectModules = Join-Path (Split-Path -Parent $PSScriptRoot) 'functions\node_modules'
  if (-not (Test-Path -LiteralPath $projectModules)) {
    $projectModules = 'C:\development\horario_ucr-main\functions\node_modules'
  }
  if (-not (Test-Path -LiteralPath (Join-Path $projectModules 'firebase-admin'))) {
    throw 'No se encuentran firebase-admin y firebase-functions en functions/node_modules del proyecto.'
  }
  $env:NODE_PATH = $cachedModules + [IO.Path]::PathSeparator + $projectModules
  & node --test --test-reporter=spec (Join-Path $PSScriptRoot 'security_tests\backend_validator.test.cjs')
  if ($LASTEXITCODE -ne 0) { throw 'Fallaron las pruebas del validador. No se inicia el emulador.' }
  $env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8186'
  $javaArguments = @('-Duser.language=en', '-Duser.country=US', '-jar', ('"' + $emulatorJar + '"'), '--host', '127.0.0.1', '--port', '8186', '--project_id', 'demo-declaraucr-backend', '--single_project_mode', 'true', '--rules', 'security_tests/backend.firestore.rules')
  Write-Host 'Iniciando Firestore local. No se usa Firebase real.'
  $emulatorProcess = Start-Process -FilePath $javaRuntime -ArgumentList $javaArguments -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $PSScriptRoot 'emulator-output.log') -RedirectStandardError (Join-Path $PSScriptRoot 'emulator-errors.log')
  $ready = $false
  for ($attempt = 0; $attempt -lt 60; $attempt++) {
    if ($emulatorProcess.HasExited) { throw 'El emulador no pudo iniciar. Revisa emulator-errors.log.' }
    $socket = New-Object System.Net.Sockets.TcpClient
    try { $socket.Connect('127.0.0.1', 8186); $ready = $true } catch {} finally { $socket.Dispose() }
    if ($ready) { break }
    Start-Sleep -Seconds 1
  }
  if (-not $ready) { throw 'El emulador no respondio en 60 segundos.' }
  & node (Join-Path $PSScriptRoot 'security_tests/backend_schedule_emulator.test.cjs')
  if ($LASTEXITCODE -ne 0) { throw 'Una o mas pruebas fallaron. Comparte backend-results.json y los registros.' }
  Write-Host 'Pruebas completadas. Abre backend-results.json para ver los resultados.' -ForegroundColor Green
} finally {
  if ($emulatorProcess -and -not $emulatorProcess.HasExited) { Stop-Process -Id $emulatorProcess.Id }
  $env:NODE_PATH = $oldNodePath
  $env:FIRESTORE_EMULATOR_HOST = $oldEmulatorHost
}



