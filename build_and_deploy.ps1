# Third Eye - Automated Build & CM4 Deployment Script
# Run this to build the app AND configure CM4 automatically

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Third Eye - Build & Deploy" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Check for CM4 boot partition
Write-Host "[1/4] Checking for CM4 boot partition..." -ForegroundColor Yellow

$bootDrive = $null
$possibleDrives = @("D:", "E:", "F:", "G:", "H:")

foreach ($drive in $possibleDrives) {
    if (Test-Path "$drive\bootcode.bin") {
        $bootDrive = $drive
        Write-Host "  Found CM4 boot partition at $drive\" -ForegroundColor Green
        break
    }
}

if ($bootDrive) {
    # Step 2: Copy setup script
    Write-Host "[2/4] Copying setup script to CM4..." -ForegroundColor Yellow

    if (Test-Path "firstrun_complete.sh") {
        Copy-Item "firstrun_complete.sh" "$bootDrive\firstrun.sh" -Force
        Write-Host "  [OK] firstrun.sh copied to $bootDrive\" -ForegroundColor Green
        Write-Host "  [OK] CM4 will auto-configure on next boot" -ForegroundColor Green
    } else {
        Write-Host "  [ERROR] firstrun_complete.sh not found!" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "  [WARNING] CM4 boot partition not found" -ForegroundColor Yellow
    Write-Host "  Insert CM4 SD card and run again to configure" -ForegroundColor Yellow
    Write-Host "  Continuing with app build only..." -ForegroundColor Yellow
}

Write-Host ""

# Step 3: Install Flutter dependencies
Write-Host "[3/4] Installing Flutter dependencies..." -ForegroundColor Yellow
flutter pub get
if ($LASTEXITCODE -ne 0) {
    Write-Host "  [ERROR] Flutter pub get failed!" -ForegroundColor Red
    exit 1
}
Write-Host "  [OK] Dependencies installed" -ForegroundColor Green
Write-Host ""

# Step 4: Build and run Flutter app
Write-Host "[4/4] Building and running app..." -ForegroundColor Yellow
flutter run
if ($LASTEXITCODE -ne 0) {
    Write-Host "  [ERROR] Flutter run failed!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Build Complete!" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Cyan

if ($bootDrive) {
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Yellow
    Write-Host "  1. Eject SD card from computer" -ForegroundColor White
    Write-Host "  2. Insert into CM4" -ForegroundColor White
    Write-Host "  3. Power on CM4 (wait 10 minutes for setup)" -ForegroundColor White
    Write-Host "  4. Open Third Eye app on phone" -ForegroundColor White
    Write-Host "  5. Cameras appear automatically!" -ForegroundColor White
}
