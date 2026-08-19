$ErrorActionPreference = 'Stop'

# Local-only concurrency regression for idempotent and conflicting Race Result
# recordings. It never reads a linked project or remote credentials.
$containerName = 'supabase_db_supabase'
$testRoot = Split-Path -Parent $PSCommandPath
$setupFile = Join-Path $testRoot 'race_results_concurrency_setup_v0_4.sql'
$sameSessionAFile = Join-Path $testRoot 'race_results_concurrency_same_session_a_v0_4.sql'
$sameSessionBFile = Join-Path $testRoot 'race_results_concurrency_same_session_b_v0_4.sql'
$conflictSessionAFile = Join-Path $testRoot 'race_results_concurrency_conflict_session_a_v0_4.sql'
$conflictSessionBFile = Join-Path $testRoot 'race_results_concurrency_conflict_session_b_v0_4.sql'
$verifyFile = Join-Path $testRoot 'race_results_concurrency_verify_v0_4.sql'

Get-Content -Raw $setupFile | docker exec -i $containerName psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q -o /dev/null
if ($LASTEXITCODE -ne 0) {
  throw 'Could not create the local Race Results concurrency fixture.'
}

foreach ($sessionFile in @($sameSessionAFile, $sameSessionBFile, $conflictSessionAFile, $conflictSessionBFile)) {
  $containerPath = "${containerName}:/tmp/$(Split-Path -Leaf $sessionFile)"
  docker cp $sessionFile $containerPath
  if ($LASTEXITCODE -ne 0) {
    throw "Could not copy the local Race Results concurrency script: $sessionFile"
  }
}

function Invoke-RaceResultConcurrentPhase([string]$SessionAFile, [string]$SessionBFile, [string]$Label) {
  $sessionAContainerFile = "/tmp/$(Split-Path -Leaf $SessionAFile)"
  $sessionBContainerFile = "/tmp/$(Split-Path -Leaf $SessionBFile)"
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
    throw "$Label session A never reached its deliberate confirmed-entry lock window."
  }

  docker exec $containerName psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q -o /dev/null -f $sessionBContainerFile
  if ($LASTEXITCODE -ne 0) {
    throw "$Label session B failed while waiting for the confirmed-entry lock."
  }

  $sessionA.WaitForExit()
  if ($sessionA.ExitCode -ne 0) {
    throw "$Label session A failed while recording the Race Result."
  }
}

Invoke-RaceResultConcurrentPhase $sameSessionAFile $sameSessionBFile 'same-facts retry'
Invoke-RaceResultConcurrentPhase $conflictSessionAFile $conflictSessionBFile 'different-facts conflict'

Get-Content -Raw $verifyFile | docker exec -i $containerName psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q -o /dev/null
if ($LASTEXITCODE -ne 0) {
  throw 'Race Results concurrency verification failed.'
}
