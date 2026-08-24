$ErrorActionPreference = 'Stop'

# Local-only concurrency regression. It never uses a linked or remote project.
$containerName = 'supabase_db_supabase'
$testRoot = Split-Path -Parent $PSCommandPath

Get-Content -Raw (Join-Path $testRoot 'horse_stamina_health_concurrency_setup_v0_6.sql') | docker exec -i $containerName psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q -o /dev/null
if ($LASTEXITCODE -ne 0) { throw 'Could not create the local v0.6-A concurrency fixture.' }

$phaseNames = @('same_request', 'parallel_results', 'manual_post', 'record_void', 'void_manual', 'correction_void')
foreach ($phase in $phaseNames) {
  foreach ($side in @('a', 'b')) {
    $name = "horse_stamina_health_${phase}_session_${side}_v0_6.sql"
    docker cp (Join-Path $testRoot $name) "${containerName}:/tmp/$name"
    if ($LASTEXITCODE -ne 0) { throw "Could not copy $name" }
  }
}

foreach ($phase in $phaseNames) {
  $sessionAName = "horse_stamina_health_${phase}_session_a_v0_6.sql"
  $sessionBName = "horse_stamina_health_${phase}_session_b_v0_6.sql"
  $applicationName = "horse_health_${phase}_session_a"
  $sessionA = Start-Process -FilePath 'docker.exe' -ArgumentList @('exec', '-e', "PGAPPNAME=$applicationName", $containerName, 'psql', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-q', '-o', '/dev/null', '-f', "/tmp/$sessionAName") -WindowStyle Hidden -PassThru
  $deadline = [DateTime]::UtcNow.AddSeconds(5)
  $sleepObserved = $false
  while ([DateTime]::UtcNow -lt $deadline) {
    $sleepObserved = ((docker exec $containerName psql -U postgres -d postgres -tAc "select exists (select 1 from pg_stat_activity where application_name = '$applicationName' and query like '%pg_sleep(3)%');").Trim() -eq 't')
    if ($sleepObserved) { break }
    Start-Sleep -Milliseconds 100
  }
  if (-not $sleepObserved) { Wait-Process -Id $sessionA.Id -ErrorAction SilentlyContinue; throw "$phase session A never reached its lock window." }
  docker exec $containerName psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q -o /dev/null -f "/tmp/$sessionBName"
  if ($LASTEXITCODE -ne 0) { throw "$phase session B failed while waiting for the intended lock." }
  $sessionA.WaitForExit()
  if ($sessionA.ExitCode -ne 0) { throw "$phase session A failed." }
}

Get-Content -Raw (Join-Path $testRoot 'horse_stamina_health_concurrency_verify_v0_6.sql') | docker exec -i $containerName psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q -o /dev/null
if ($LASTEXITCODE -ne 0) { throw 'v0.6-A concurrency verification failed.' }
Write-Output 'PASS horse stamina / post-race health concurrency'
