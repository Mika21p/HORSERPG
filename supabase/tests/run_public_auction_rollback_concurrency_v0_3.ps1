$ErrorActionPreference = 'Stop'

# Local-only runner for the rollback lock-order regression. It starts two
# independent psql sessions against the local Supabase Docker database; it
# never reads a linked project or uses remote credentials.
$containerName = 'supabase_db_supabase'
$testRoot = Split-Path -Parent $PSCommandPath
$setupFile = Join-Path $testRoot 'public_auction_rollback_concurrency_setup_v0_3.sql'
$sessionAFile = Join-Path $testRoot 'public_auction_rollback_concurrency_session_a_v0_3.sql'
$sessionBFile = Join-Path $testRoot 'public_auction_rollback_concurrency_session_b_v0_3.sql'
$verifyFile = Join-Path $testRoot 'public_auction_rollback_concurrency_verify_v0_3.sql'

Get-Content -Raw $setupFile | docker exec -i $containerName psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q -o /dev/null
if ($LASTEXITCODE -ne 0) {
  throw 'Could not create the local rollback-concurrency fixture.'
}

foreach ($sessionFile in @($sessionAFile, $sessionBFile)) {
  $containerPath = "${containerName}:/tmp/$(Split-Path -Leaf $sessionFile)"
  docker cp $sessionFile $containerPath
  if ($LASTEXITCODE -ne 0) {
    throw "Could not copy the local concurrency session script: $sessionFile"
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
  throw 'Session A never reached its deliberate lock-holding window.'
}

docker exec $containerName psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q -o /dev/null -f $sessionBContainerFile
if ($LASTEXITCODE -ne 0) {
  throw 'Session B failed while waiting to confirm the rollback request.'
}

$sessionA.WaitForExit()
if ($sessionA.ExitCode -ne 0) {
  throw 'Session A failed while retrying the rollback request.'
}

Get-Content -Raw $verifyFile | docker exec -i $containerName psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q -o /dev/null
if ($LASTEXITCODE -ne 0) {
  throw 'Rollback-concurrency verification failed.'
}
