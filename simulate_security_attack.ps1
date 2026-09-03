# ═══════════════════════════════════════════════════════════════════════════════
# simulate_security_attack.ps1 — Simulación de Ataque a PostgreSQL en RDS
# ═══════════════════════════════════════════════════════════════════════════════

param (
    [Parameter(Mandatory = $false)]
    [int]$Attempts = 15,

    [Parameter(Mandatory = $false)]
    [string]$Region = "us-east-1"
)

Write-Host "`n========================================================" -ForegroundColor Red
Write-Host " [SEGURIDAD SRE] Simulando Ataque de Autenticación Fallida" -ForegroundColor Red
Write-Host " Target: RDS PostgreSQL (koncilia-data-db)" -ForegroundColor Yellow
Write-Host "========================================================`n" -ForegroundColor Red

# 1. Publicar métrica limpia directamente a CloudWatch Metrics (Actualización inmediata en Dashboard)
aws cloudwatch put-metric-data `
  --namespace "SecurityGoldenSignals" `
  --metric-name "FailedDBAuthentications" `
  --value $Attempts `
  --unit "Count" `
  --region $Region

Write-Host "  -> [OK] Métrica FailedDBAuthentications incrementada en +$Attempts." -ForegroundColor Green
Write-Host "  -> [OK] Intentos de fuerza bruta registrados en CloudWatch." -ForegroundColor Green

Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host " [OK] Dashboard 'Security-Golden-Signals' Actualizado" -ForegroundColor Cyan
Write-Host "========================================================`n" -ForegroundColor Cyan
