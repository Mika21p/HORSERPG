$ErrorActionPreference = 'Stop'

# Local-only concurrency regression for retirement confirmation against record,
# correction, and void. It uses only the Docker development database.
$containerName = 'supabase_db_supabase'
$testRoot = Split-Path -Parent $PSCommandPath

function Invoke-LocalSqlFile([string]$fileName) {
  $path = Join-Path $testRoot $fileName
  Get-Content -Raw $path | docker exec -i $containerName psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q -o /dev/null
  if ($LASTEXITCODE -ne 0) { throw "Local SQL test failed: $fileName" }
}

function Start-LocalSqlFile([string]$fileName) {
  $path = Join-Path $testRoot $fileName
  $containerPath = "${containerName}:/tmp/$fileName"
  docker cp $path $containerPath
  if ($LASTEXITCODE -ne 0) { throw "Could not copy local SQL session: $fileName" }
  return Start-Process -FilePath 'docker.exe' -ArgumentList @(
    'exec', $containerName, 'psql', '-U', 'postgres', '-d', 'postgres',
    '-v', 'ON_ERROR_STOP=1', '-q', '-o', '/dev/null', '-f', "/tmp/$fileName"
  ) -WindowStyle Hidden -PassThru
}

function Invoke-ContendedPair([string]$sessionA, [string]$sessionB) {
  $processA = Start-LocalSqlFile $sessionA
  $deadline = [DateTime]::UtcNow.AddSeconds(4)
  $sleepObserved = $false
  while ([DateTime]::UtcNow -lt $deadline) {
    $sleepObserved = ((docker exec $containerName psql -U postgres -d postgres -tAc "select exists (select 1 from pg_stat_activity where query like '%pg_sleep(3)%');").Trim() -eq 't')
    if ($sleepObserved) { break }
    Start-Sleep -Milliseconds 100
  }
  if (-not $sleepObserved) {
    Wait-Process -Id $processA.Id -ErrorAction SilentlyContinue
    throw "Session A did not reach its controlled Horse-lock window: $sessionA"
  }
  Invoke-LocalSqlFile $sessionB
  $processA.WaitForExit()
  if ($processA.ExitCode -ne 0) { throw "Concurrent Session A failed: $sessionA" }
}

Invoke-LocalSqlFile 'retirement_prize_release_concurrency_setup_v0_4.sql'
Invoke-ContendedPair 'retirement_prize_release_concurrency_confirm_correction_session_a_v0_4.sql' 'retirement_prize_release_concurrency_correction_session_b_v0_4.sql'
Invoke-ContendedPair 'retirement_prize_release_concurrency_confirm_void_session_a_v0_4.sql' 'retirement_prize_release_concurrency_void_session_b_v0_4.sql'
Invoke-ContendedPair 'retirement_prize_release_concurrency_confirm_record_session_a_v0_4.sql' 'retirement_prize_release_concurrency_record_session_b_v0_4.sql'

$parallelA = Start-LocalSqlFile 'retirement_prize_release_concurrency_parallel_session_a_v0_4.sql'
$deadline = [DateTime]::UtcNow.AddSeconds(4)
while ([DateTime]::UtcNow -lt $deadline) {
  if (((docker exec $containerName psql -U postgres -d postgres -tAc "select exists (select 1 from pg_stat_activity where query like '%pg_sleep(3)%');").Trim()) -eq 't') { break }
  Start-Sleep -Milliseconds 100
}
$stopwatch = [Diagnostics.Stopwatch]::StartNew()
Invoke-LocalSqlFile 'retirement_prize_release_concurrency_parallel_session_b_v0_4.sql'
$stopwatch.Stop()
$parallelA.WaitForExit()
if ($parallelA.ExitCode -ne 0) { throw 'Different-Horse parallel Session A failed.' }
if ($stopwatch.Elapsed.TotalSeconds -ge 2.5) { throw 'Different-Horse retirement confirmation was unnecessarily serialized.' }

Invoke-LocalSqlFile 'retirement_prize_release_concurrency_verify_v0_4.sql'
Write-Output 'PASS retirement/prize release concurrency'
