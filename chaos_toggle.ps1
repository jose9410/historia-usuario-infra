# ═══════════════════════════════════════════════════════════════════════════════
# chaos_toggle.ps1 — Inyección y Restauración de Chaos Engineering en AWS ECS
# ═══════════════════════════════════════════════════════════════════════════════

param (
    [Parameter(Mandatory = $false)]
    [ValidateSet("enable", "disable")]
    [string]$Action = "enable",

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
    Write-Host "  - qa-automation-api : CHAOS_LATENCY_ENABLED = true (600ms)" -ForegroundColor Yellow
    Write-Host "  - data-service      : CHAOS_ERROR_ENABLED   = true (10% 500s)" -ForegroundColor Yellow
    Write-Host ""
    $QaLatency   = "true"
    $QaLatencyMs = "600"
    $DataError   = "true"
} else {
    Write-Host "`n========================================================" -ForegroundColor Green
    Write-Host " [RESTORE] Desactivando Caos y Restaurando Estado Normal" -ForegroundColor Green
    Write-Host "========================================================" -ForegroundColor Green
    Write-Host "  - qa-automation-api : CHAOS_LATENCY_ENABLED = false" -ForegroundColor Gray
    Write-Host "  - data-service      : CHAOS_ERROR_ENABLED   = false" -ForegroundColor Gray
    Write-Host ""
    $QaLatency   = "false"
    $QaLatencyMs = "200"
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
# 1. QA-AUTOMATION-API-SERVICE (Inyección de Latencia)
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "[1/2] Procesando qa-automation-api-service..." -ForegroundColor Cyan

$rawQaJson = aws ecs describe-task-definition --task-definition qa-automation-api-task --region $Region --query "taskDefinition" | Out-String
if (-not [string]::IsNullOrWhiteSpace($rawQaJson)) {
    $taskDefQa = $rawQaJson | ConvertFrom-Json
    $taskDefQa = Clean-TaskDefinitionJson $taskDefQa

    $qaContainer = $taskDefQa.containerDefinitions | Where-Object { $_.name -eq "qa-automation-api" }
    if ($qaContainer) {
        # Filtrar variables previas de caos
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
            --region $Region `
            --force-new-deployment | Out-Null

        Write-Host "  -> Nueva revisión registrada: $newQaArn" -ForegroundColor Yellow
        Write-Host "  -> Servicio qa-automation-api-service actualizado con éxito." -ForegroundColor Green
    } else {
        Write-Host "  [!] Error: No se encontró el contenedor 'qa-automation-api' en la definición." -ForegroundColor Red
    }
} else {
    Write-Host "  [!] Error al obtener la definición de qa-automation-api-task." -ForegroundColor Red
}

# ─────────────────────────────────────────────────────────────────────────────
# 2. DATA-SERVICE-SERVICE (Inyección de Tasa de Error 500)
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`n[2/2] Procesando data-service-service..." -ForegroundColor Cyan

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
            --region $Region `
            --force-new-deployment | Out-Null

        Write-Host "  -> Nueva revisión registrada: $newDataArn" -ForegroundColor Yellow
        Write-Host "  -> Servicio data-service-service actualizado con éxito." -ForegroundColor Green
    } else {
        Write-Host "  [!] Error: No se encontró el contenedor 'data-service' en la definición." -ForegroundColor Red
    }
} else {
    Write-Host "  [!] Error al obtener la definición de data-service-task." -ForegroundColor Red
}

Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host " [OK] Operación de Caos completada exitosamente en ECS" -ForegroundColor Cyan
Write-Host "========================================================`n" -ForegroundColor Cyan
