# ═══════════════════════════════════════════════════════════════════════════════
# chaos_toggle.ps1 — Inyección y Restauración de Chaos Engineering en AWS ECS
# ═══════════════════════════════════════════════════════════════════════════════

param (
    [Parameter(Mandatory = $false)]
    [ValidateSet("enable", "disable")]
    [string]$Action = "enable",

    [Parameter(Mandatory = $false)]
    [int]$LatencyMs = 3000,

    [Parameter(Mandatory = $false)]
    [string]$Region = "us-east-1",

    [Parameter(Mandatory = $false)]
    [string]$ClusterName = "koncilia-cluster"
)

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

if ($Action -eq "enable") {
    Write-Host "`n========================================================" -ForegroundColor Red
    Write-Host " [CHAOS ENGINEERING] Inyectando Caos en AWS ECS Fargate" -ForegroundColor Red
    Write-Host "========================================================" -ForegroundColor Red
    Write-Host "  - qa-automation-api : CHAOS_LATENCY_ENABLED = true ($($LatencyMs)ms)" -ForegroundColor Yellow
    Write-Host "  - data-service      : CHAOS_ERROR_ENABLED   = true (10% 500s)" -ForegroundColor Yellow
    Write-Host ""
    $QaLatency   = "true"
    $QaLatencyMs = "$LatencyMs"
    $DataError   = "true"
} else {
    Write-Host "`n========================================================" -ForegroundColor Green
    Write-Host " [RESTORE] Desactivando Caos y Restaurando Estado Normal" -ForegroundColor Green
    Write-Host "========================================================" -ForegroundColor Green
    Write-Host "  - qa-automation-api : CHAOS_LATENCY_ENABLED = false" -ForegroundColor Gray
    Write-Host "  - data-service      : CHAOS_ERROR_ENABLED   = false" -ForegroundColor Gray
    Write-Host ""
    $QaLatency   = "false"
    $QaLatencyMs = "0"
    $DataError   = "false"
}

# ─────────────────────────────────────────────────────────────────────────────
# Helper: Limpia metadatos de sólo lectura de AWS Task Definition
# ─────────────────────────────────────────────────────────────────────────────
function Clean-TaskDefinitionJson ($taskDef) {
    $readonlyFields = @(
        'taskDefinitionArn',
        'revision',
        'status',
        'requiresAttributes',
        'compatibilities',
        'registeredAt',
        'registeredBy'
    )
    foreach ($field in $readonlyFields) {
        if ($taskDef.PSObject.Properties[$field]) {
            $taskDef.PSObject.Properties.Remove($field)
        }
    }
    return $taskDef
}

# ─────────────────────────────────────────────────────────────────────────────
# 1. QA-AUTOMATION-API-SERVICE
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "[1/2] Actualizando qa-automation-api-service..." -ForegroundColor Cyan

$rawQaJson = aws ecs describe-task-definition --task-definition qa-automation-api-task --region $Region --query "taskDefinition" | Out-String
if (-not [string]::IsNullOrWhiteSpace($rawQaJson)) {
    $taskDefQa = $rawQaJson | ConvertFrom-Json
    $taskDefQa = Clean-TaskDefinitionJson $taskDefQa

    $qaContainer = $taskDefQa.containerDefinitions | Where-Object { $_.name -eq "qa-automation-api" }
    if ($qaContainer) {
        $filteredEnv = @($qaContainer.environment | Where-Object { $_.name -notin @("CHAOS_LATENCY_ENABLED", "CHAOS_LATENCY_MS") })
        $filteredEnv += @(
            [PSCustomObject]@{ name = "CHAOS_LATENCY_ENABLED"; value = $QaLatency },
            [PSCustomObject]@{ name = "CHAOS_LATENCY_MS"; value = $QaLatencyMs }
        )
        $qaContainer.environment = $filteredEnv

        $tempQaFile = "$PWD\temp_qa_taskdef.json"
        $cleanQaJson = $taskDefQa | ConvertTo-Json -Depth 20
        [System.IO.File]::WriteAllText($tempQaFile, $cleanQaJson, $utf8NoBom)

        $newQaArn = aws ecs register-task-definition --cli-input-json "file://$tempQaFile" --region $Region --query "taskDefinition.taskDefinitionArn" --output text
        Remove-Item $tempQaFile -Force -ErrorAction SilentlyContinue

        aws ecs update-service `
            --cluster $ClusterName `
            --service qa-automation-api-service `
            --task-definition $newQaArn `
            --desired-count 1 `
            --region $Region `
            --force-new-deployment | Out-Null

        Write-Host "  -> Nueva revisión: $newQaArn" -ForegroundColor Yellow
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# 2. DATA-SERVICE-SERVICE
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "[2/2] Actualizando data-service-service..." -ForegroundColor Cyan

$rawDataJson = aws ecs describe-task-definition --task-definition data-service-task --region $Region --query "taskDefinition" | Out-String
if (-not [string]::IsNullOrWhiteSpace($rawDataJson)) {
    $taskDefData = $rawDataJson | ConvertFrom-Json
    $taskDefData = Clean-TaskDefinitionJson $taskDefData

    $dataContainer = $taskDefData.containerDefinitions | Where-Object { $_.name -eq "data-service" }
    if ($dataContainer) {
        $filteredDataEnv = @($dataContainer.environment | Where-Object { $_.name -ne "CHAOS_ERROR_ENABLED" })
        $filteredDataEnv += @(
            [PSCustomObject]@{ name = "CHAOS_ERROR_ENABLED"; value = $DataError }
        )
        $dataContainer.environment = $filteredDataEnv

        $tempDataFile = "$PWD\temp_data_taskdef.json"
        $cleanDataJson = $taskDefData | ConvertTo-Json -Depth 20
        [System.IO.File]::WriteAllText($tempDataFile, $cleanDataJson, $utf8NoBom)

        $newDataArn = aws ecs register-task-definition --cli-input-json "file://$tempDataFile" --region $Region --query "taskDefinition.taskDefinitionArn" --output text
        Remove-Item $tempDataFile -Force -ErrorAction SilentlyContinue

        aws ecs update-service `
            --cluster $ClusterName `
            --service data-service-service `
            --task-definition $newDataArn `
            --desired-count 1 `
            --region $Region `
            --force-new-deployment | Out-Null

        Write-Host "  -> Nueva revisión: $newDataArn" -ForegroundColor Yellow
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# 3. ROTACIÓN INMEDIATA DE TAREAS (Sin esperar el draining lento de Fargate)
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`n[+] Aplicando cambio inmediato en Fargate..." -ForegroundColor Cyan

$oldQaTasks = aws ecs list-tasks --cluster $ClusterName --service-name qa-automation-api-service --region $Region --query "taskArns[]" --output text
foreach ($t in ($oldQaTasks -split "`t")) {
    if ($t -and $t -ne "None") { aws ecs stop-task --cluster $ClusterName --task $t --region $Region --reason "Chaos toggle transition" 2>$null | Out-Null }
}

$oldDataTasks = aws ecs list-tasks --cluster $ClusterName --service-name data-service-service --region $Region --query "taskArns[]" --output text
foreach ($t in ($oldDataTasks -split "`t")) {
    if ($t -and $t -ne "None") { aws ecs stop-task --cluster $ClusterName --task $t --region $Region --reason "Chaos toggle transition" 2>$null | Out-Null }
}

Write-Host "  -> Tareas anteriores recicladas. ECS iniciando nuevas instancias en caliente..." -ForegroundColor Green

Write-Host "`n========================================================" -ForegroundColor Cyan
if ($Action -eq "enable") {
    Write-Host " [OK] Caos HABILITADO (+3.0s de latencia en cada petición)" -ForegroundColor Red
} else {
    Write-Host " [OK] Caos DESHABILITADO (Restaurado a <1.2s normal)" -ForegroundColor Green
}
Write-Host "========================================================`n" -ForegroundColor Cyan
