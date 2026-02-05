# Script de Build de Produção - V10 Delivery
# Versão 1.0.1+4

Write-Host "🚀 Iniciando build de produção do V10 Delivery..." -ForegroundColor Cyan
Write-Host ""

# 1. Clean
Write-Host "🧹 Limpando cache e builds anteriores..." -ForegroundColor Yellow
flutter clean
if ($LASTEXITCODE -ne 0) { 
    Write-Host "❌ Erro no flutter clean" -ForegroundColor Red
    exit 1 
}

# 2. Get dependencies
Write-Host ""
Write-Host "📦 Baixando dependências..." -ForegroundColor Yellow
flutter pub get
if ($LASTEXITCODE -ne 0) { 
    Write-Host "❌ Erro no flutter pub get" -ForegroundColor Red
    exit 1 
}

# 3. Build APK
Write-Host ""
Write-Host "🔨 Gerando APK de produção..." -ForegroundColor Yellow
flutter build apk --release
if ($LASTEXITCODE -ne 0) { 
    Write-Host "❌ Erro no flutter build apk" -ForegroundColor Red
    exit 1 
}

Write-Host ""
Write-Host "✅ Build concluído com sucesso!" -ForegroundColor Green
Write-Host ""
Write-Host "📍 APK gerado em: build\app\outputs\flutter-apk\app-release.apk" -ForegroundColor Cyan
Write-Host ""
