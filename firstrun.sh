#!/bin/bash
# firstrun.sh - Stage 1: Install systemd service (NO network required)
# Logs explicitly written to ensure they work with systemd.run

LOG="/boot/firmware/firstrun-install.log"

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"
}

# Start logging
log "=========================================="
log "STAGE 1: Installing setup service"
log "=========================================="

log "Checking boot partition..."
if [ -f /boot/firmware/cm4_setup_with_hotspot.sh ]; then
    log "✓ Found setup script on boot partition"
else
    log "✗ ERROR: cm4_setup_with_hotspot.sh not found!"
    exit 1
fi

log "Copying setup script to /usr/local/bin..."
cp /boot/firmware/cm4_setup_with_hotspot.sh /usr/local/bin/ 2>> "$LOG"
chmod +x /usr/local/bin/cm4_setup_with_hotspot.sh 2>> "$LOG"
log "✓ Setup script copied"

log "Creating systemd service..."
cat > /etc/systemd/system/thirdeye-setup.service << 'EOFSVC'
[Unit]
Description=Third Eye Complete Setup with Network
After=network-online.target
Wants=network-online.target
ConditionPathExists=!/home/anton/.thirdeye-complete

[Service]
Type=oneshot
ExecStart=/usr/local/bin/cm4_setup_with_hotspot.sh
RemainAfterExit=yes
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=multi-user.target
EOFSVC

log "✓ Service file created"

log "Enabling thirdeye-setup service..."
systemctl daemon-reload 2>> "$LOG"
systemctl enable thirdeye-setup.service 2>> "$LOG"
log "✓ Service enabled"

log "Removing firstrun.sh (self-delete)..."
rm -f /boot/firmware/firstrun.sh 2>> "$LOG"
log "✓ firstrun.sh removed"

log "=========================================="
log "STAGE 1 COMPLETE - Rebooting for Stage 2"
log "=========================================="

sync
reboot
