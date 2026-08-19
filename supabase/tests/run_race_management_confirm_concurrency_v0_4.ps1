$ErrorActionPreference = 'Stop'

# Local-only runner for both competing request confirmations and a direct-GM
# schedule versus request confirmation against one Horse/final WP week. It
# never invokes a linked or remote Supabase project.
$containerName = 'supabase_db_supabase'
$testRoot = Split-Path -Parent $PSCommandPath
$setupFile = Join-Path $testRoot 'race_management_confirm_concurrency_setup_v0_4.sql'
$sessionAFile = Join-Path $testRoot 'race_management_confirm_concurrency_session_a_v0_4.sql'
$sessionBFile = Join-Path $testRoot 'race_management_confirm_concurrency_session_b_v0_4.sql'
$directSessionAFile = Join-Path $testRoot 'race_management_direct_confirm_concurrency_session_a_v0_4.sql'
$directSessionBFile = Join-Path $testRoot 'race_management_direct_confirm_concurrency_session_b_v0_4.sql'
$verifyFile = Join-Path $testRoot 'race_management_confirm_concurrency_verify_v0_4.sql'

Get-Content -Raw $setupFile | docker exec -i $containerName psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q -o /dev/null
if ($LASTEXITCODE -ne 0) {
  throw 'Could not create the local Race Management concurrency fixture.'
}

foreach ($sessionFile in @($sessionAFile, $sessionBFile, $directSessionAFile, $directSessionBFile)) {
  $containerPath = "${containerName}:/tmp/$(Split-Path -Leaf $sessionFile)"
  docker cp $sessionFile $containerPath
  if ($LASTEXITCODE -ne 0) {
    throw "Could not copy the local Race Management concurrency script: $sessionFile"
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
  throw 'Session A never reached its deliberate Horse-lock holding window.'
}

docker exec $containerName psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q -o /dev/null -f $sessionBContainerFile
if ($LASTEXITCODE -ne 0) {
  throw 'Session B failed while waiting for the Race Management Horse lock.'
}

$sessionA.WaitForExit()
if ($sessionA.ExitCode -ne 0) {
  throw 'Session A failed while confirming the Race Management request.'
}

$directSessionAContainerFile = "/tmp/$(Split-Path -Leaf $directSessionAFile)"
$directSessionBContainerFile = "/tmp/$(Split-Path -Leaf $directSessionBFile)"
$directSessionA = Start-Process -FilePath 'docker.exe' -ArgumentList @(
  'exec', $containerName, 'psql', '-U', 'postgres', '-d', 'postgres',
  '-v', 'ON_ERROR_STOP=1', '-q', '-o', '/dev/null', '-f', $directSessionAContainerFile
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
  Wait-Process -Id $directSessionA.Id -ErrorAction SilentlyContinue
  throw 'Direct GM Session A never reached its deliberate Horse-lock holding window.'
}

docker exec $containerName psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q -o /dev/null -f $directSessionBContainerFile
if ($LASTEXITCODE -ne 0) {
  throw 'Request confirmation failed while waiting for the direct GM Horse lock.'
}

$directSessionA.WaitForExit()
if ($directSessionA.ExitCode -ne 0) {
  throw 'Direct GM Session A failed while scheduling the Race Management entry.'
}

Get-Content -Raw $verifyFile | docker exec -i $containerName psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q -o /dev/null
if ($LASTEXITCODE -ne 0) {
  throw 'Race Management concurrency verification failed.'
}
