$ErrorActionPreference = 'Stop'

# Local-only concurrency regression for Race Result correction versus void.
# It never reads a linked project or remote credentials.
$containerName = 'supabase_db_supabase'
$testRoot = Split-Path -Parent $PSCommandPath
$setupFile = Join-Path $testRoot 'prize_receivables_concurrency_setup_v0_4.sql'
$sessionAFile = Join-Path $testRoot 'prize_receivables_concurrency_correction_session_a_v0_4.sql'
$sessionBFile = Join-Path $testRoot 'prize_receivables_concurrency_void_session_b_v0_4.sql'
$verifyFile = Join-Path $testRoot 'prize_receivables_concurrency_verify_v0_4.sql'

Get-Content -Raw $setupFile | docker exec -i $containerName psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q -o /dev/null
if ($LASTEXITCODE -ne 0) {
  throw 'Could not create the local Prize Receivables concurrency fixture.'
}

foreach ($sessionFile in @($sessionAFile, $sessionBFile)) {
  $containerPath = "${containerName}:/tmp/$(Split-Path -Leaf $sessionFile)"
  docker cp $sessionFile $containerPath
  if ($LASTEXITCODE -ne 0) {
    throw "Could not copy the local Prize Receivables concurrency script: $sessionFile"
  }
}

$sessionAContainerFile = "/tmp/$(Split-Path -Leaf $sessionAFile)"
$sessionBContainerFile = "/tmp/$(Split-Path -Leaf $sessionBFile)"
$sessionA = Start-Process -FilePath 'docker.exe' -ArgumentList @(
  'exec', $containerName, 'psql', '-U', 'postgres', '-d', 'postgres',
  '-v', 'ON_ERROR_STOP=1', '-q', '-o', '/dev/null', '-f', $sessionAContainerFile
) -WindowStyle Hidden -PassThru

$sleepObserved = $false
$deadline = [DateTime]::UtcNow.AddSeconds(4)
while ([DateTime]::UtcNow -lt $deadline) {
  $sleepObserved = ((docker exec $containerName psql -U postgres -d postgres -tAc "select exists (select 1 from pg_stat_activity where query like '%pg_sleep(3)%');").Trim() -eq 't')
  if ($sleepObserved) {
    break
  }
  Start-Sleep -Milliseconds 100
}

if (-not $sleepObserved) {
  Wait-Process -Id $sessionA.Id -ErrorAction SilentlyContinue
  throw 'Correction session never reached its deliberate Race Result lock window.'
}

docker exec $containerName psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q -o /dev/null -f $sessionBContainerFile
if ($LASTEXITCODE -ne 0) {
  throw 'Void session failed while waiting for the Race Result lock.'
}

$sessionA.WaitForExit()
if ($sessionA.ExitCode -ne 0) {
  throw 'Correction session failed.'
}

Get-Content -Raw $verifyFile | docker exec -i $containerName psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q -o /dev/null
if ($LASTEXITCODE -ne 0) {
  throw 'Prize Receivables concurrency verification failed.'
}

Write-Output 'PASS prize receivables correction-vs-void concurrency'
