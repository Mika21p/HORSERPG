$ErrorActionPreference = 'Stop'

# Local-only concurrency regression. It exercises the real local Docker
# database and never reads a linked project or remote credentials.
$containerName = 'supabase_db_supabase'
$testRoot = Split-Path -Parent $PSCommandPath
$setupFile = Join-Path $testRoot 'breeding_pedigree_foal_concurrency_setup_v0_5.sql'
$verifyFile = Join-Path $testRoot 'breeding_pedigree_foal_concurrency_verify_v0_5.sql'

Get-Content -Raw $setupFile | docker exec -i $containerName psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q -o /dev/null
if ($LASTEXITCODE -ne 0) {
  throw 'Could not create the local v0.5-A concurrency fixture.'
}

$phaseFiles = @(
  'breeding_pedigree_foal_activate_session_a_v0_5.sql',
  'breeding_pedigree_foal_activate_session_b_v0_5.sql',
  'breeding_pedigree_foal_deactivate_session_a_v0_5.sql',
  'breeding_pedigree_foal_deactivate_session_b_v0_5.sql',
  'breeding_pedigree_foal_same_request_session_a_v0_5.sql',
  'breeding_pedigree_foal_same_request_session_b_v0_5.sql',
  'breeding_pedigree_foal_parallel_sire_session_a_v0_5.sql',
  'breeding_pedigree_foal_parallel_sire_session_b_v0_5.sql'
)

foreach ($fileName in $phaseFiles) {
  $sessionFile = Join-Path $testRoot $fileName
  docker cp $sessionFile "${containerName}:/tmp/$fileName"
  if ($LASTEXITCODE -ne 0) {
    throw "Could not copy the local v0.5-A concurrency script: $fileName"
  }
}

function Invoke-BreedingConcurrentPhase([string]$SessionAName, [string]$SessionBName, [string]$Label) {
  $sessionA = Start-Process -FilePath 'docker.exe' -ArgumentList @(
    'exec', $containerName, 'psql', '-U', 'postgres', '-d', 'postgres',
    '-v', 'ON_ERROR_STOP=1', '-q', '-o', '/dev/null', '-f', "/tmp/$SessionAName"
  ) -WindowStyle Hidden -PassThru

  $sleepObserved = $false
  $deadline = [DateTime]::UtcNow.AddSeconds(4)
  while ([DateTime]::UtcNow -lt $deadline) {
    $sleepObserved = ((docker exec $containerName psql -U postgres -d postgres -tAc "select exists (select 1 from pg_stat_activity where query like '%pg_sleep(2)%');").Trim() -eq 't')
    if ($sleepObserved) { break }
    Start-Sleep -Milliseconds 100
  }

  if (-not $sleepObserved) {
    Wait-Process -Id $sessionA.Id -ErrorAction SilentlyContinue
    throw "$Label session A never reached its deliberate lock window."
  }

  docker exec $containerName psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q -o /dev/null -f "/tmp/$SessionBName"
  if ($LASTEXITCODE -ne 0) {
    throw "$Label session B failed while waiting for the intended lock."
  }

  $sessionA.WaitForExit()
  if ($sessionA.ExitCode -ne 0) {
    throw "$Label session A failed."
  }
}

Invoke-BreedingConcurrentPhase 'breeding_pedigree_foal_activate_session_a_v0_5.sql' 'breeding_pedigree_foal_activate_session_b_v0_5.sql' 'candidate activate versus activate'
Invoke-BreedingConcurrentPhase 'breeding_pedigree_foal_deactivate_session_a_v0_5.sql' 'breeding_pedigree_foal_deactivate_session_b_v0_5.sql' 'candidate deactivate versus deactivate'
Invoke-BreedingConcurrentPhase 'breeding_pedigree_foal_same_request_session_a_v0_5.sql' 'breeding_pedigree_foal_same_request_session_b_v0_5.sql' 'same Foal request retry'
Invoke-BreedingConcurrentPhase 'breeding_pedigree_foal_parallel_sire_session_a_v0_5.sql' 'breeding_pedigree_foal_parallel_sire_session_b_v0_5.sql' 'parallel same-sire Foal creation'

Get-Content -Raw $verifyFile | docker exec -i $containerName psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q -o /dev/null
if ($LASTEXITCODE -ne 0) {
  throw 'v0.5-A concurrency verification failed.'
}
