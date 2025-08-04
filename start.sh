#!/bin/bash
set -e

# Configuration variables
DISK="/data/vm.raw"
IMG="/opt/qemu/${OS_TYPE}.img"
SEED="/opt/qemu/seed.iso"
PORT_SSH=2221
PORT_VNC=6080
USERNAME="root"
PASSWORD="root"
QEMU_PIDFILE="/var/run/qemu.pid"
LOG_FILE="/var/log/vm-startup.log"

# Log function for better debugging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

# Initialize log file
mkdir -p /var/log
> $LOG_FILE

# Check if shell mode is enabled
if [ "$OS_TYPE" = "shell" ]; then
    log "Starting shell mode..."
    echo "Container is running in shell mode. Use 'bash' to interact."
    tail -f /dev/null
fi

# --- FIX START ---
# Run the OS configuration script to download the necessary images.
# This must be done before checking if the image files exist.
log "Running OS configuration script..."
/bin/bash /os-config.sh

# Now that os-config.sh has run, the image files should exist.
# We no longer need the explicit checks here.
# The disk creation logic below will handle errors if the source image is missing.
# --- FIX END ---

# Check if KVM is available
if [ -e /dev/kvm ]; then
    KVM="-enable-kvm -cpu host"
    log "Using KVM acceleration"
else
    log "⚠️ KVM not available, falling back to software emulation"
    KVM=""
fi

# Get public IP (fallback to localhost if failed)
IP=$(curl -s --connect-timeout 5 https://api.ipify.org || echo "localhost")
log "Detected IP: $IP"

# Create VM disk if it doesn't exist
# This is now safe to run because os-config.sh has provided the source image.
if [ ! -f "$DISK" ]; then
    log "Creating VM disk from source image ($IMG)..."
    if ! qemu-img convert -f qcow2 -O raw "$IMG" "$DISK"; then
        log "Error: Failed to convert disk image from $IMG"
        exit 1
    fi
    if ! qemu-img resize "$DISK" 50G; then
        log "Error: Failed to resize disk"
        exit 1
    fi
    log "VM disk created successfully"
fi

# Start SSH server in container
log "Starting SSH server..."
mkdir -p /var/run/sshd
/usr/sbin/sshd -o "PasswordAuthentication yes" -o "PermitRootLogin yes" || {
    log "Error: Failed to start SSH server"
    exit 1
}

# Start noVNC
log "Starting noVNC on port $PORT_VNC..."
websockify --web=/novnc $PORT_VNC localhost:5900 &
WEBSOCKIFY_PID=$!
sleep 2
if ! ps -p $WEBSOCKIFY_PID > /dev/null; then
    log "Error: Failed to start websockify"
    exit 1
fi

# Clean up previous PID file if exists
[ -f "$QEMU_PIDFILE" ] && rm "$QEMU_PIDFILE"

# QEMU configuration based on OS type
QEMU_OPTS="$KVM -smp 2 -m 2048 -drive file=$DISK,format=raw,if=virtio -netdev user,id=net0,hostfwd=tcp::${PORT_SSH}-:22 -device virtio-net-pci,netdev=net0 -vnc :0 -daemonize -pidfile $QEMU_PIDFILE -display none -serial file:/var/log/qemu-serial.log"

if [ "$OS_TYPE" = "windows7" ] || [ "$OS_TYPE" = "windows10" ] || [ "$OS_TYPE" = "windows2022" ]; then
    QEMU_OPTS="$KVM -smp 2 -m 4096 -drive file=$DISK,format=raw,if=virtio -netdev user,id=net0,hostfwd=tcp::${PORT_SSH}-:3389 -device virtio-net-pci,netdev=net0 -vnc :0 -daemonize -pidfile $QEMU_PIDFILE -display none -serial file:/var/log/qemu-serial.log -cdrom /opt/qemu/virtio-win.iso"
elif [ "$DESKTOP" = "true" ]; then
    QEMU_OPTS="$QEMU_OPTS -vga virtio -display vnc=0.0.0.0:0"
else
    # The SEED drive is used for cloud-init on non-Windows desktop systems
    QEMU_OPTS="$QEMU_OPTS -drive file=$SEED,format=raw,if=virtio,readonly=on -smbios type=1,serial=ds=nocloud"
fi

# Start QEMU
log "Starting QEMU VM for $OS_TYPE..."
qemu-system-x86_64 $QEMU_OPTS

# Verify QEMU started
sleep 5
if [ ! -f "$QEMU_PIDFILE" ]; then
    log "Error: QEMU failed to start (no PID file)"
    exit 1
fi

QEMU_PID=$(cat "$QEMU_PIDFILE")
if ! ps -p "$QEMU_PID" > /dev/null; then
    log "Error: QEMU process not running"
    exit 1
fi

# Wait for SSH (Linux) or RDP (Windows) to be available
if [ "$OS_TYPE" = "windows7" ] || [ "$OS_TYPE" = "windows10" ] || [ "$OS_TYPE" = "windows2022" ]; then
    log "Waiting for RDP on port $PORT_SSH..."
    for i in {1..60}; do
        if nc -z localhost $PORT_SSH; then
            log "✅ VM is ready (RDP available)!"
            break
        fi
        log "⏳ Waiting for RDP... (Attempt $i/60)"
        sleep 2
    done
else
    log "Waiting for SSH on port $PORT_SSH..."
    for i in {1..60}; do
        if nc -z localhost $PORT_SSH; then
            log "✅ VM is ready!"
            if sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -p $PORT_SSH $USERNAME@localhost true; then
                log "SSH authentication successful"
                break
            else
                log "SSH port open but authentication failed"
            fi
        fi
        log "⏳ Waiting for SSH... (Attempt $i/60)"
        sleep 2
    done
fi

# Print connection details
echo "================================================"
echo " 🖥️  VNC:  http://${IP}:${PORT_VNC}/vnc.html" | tee -a $LOG_FILE
if [ "$OS_TYPE" = "windows7" ] || [ "$OS_TYPE" = "windows10" ] || [ "$OS_TYPE" = "windows2022" ]; then
    echo " 🔐 RDP:  rdp://${IP}:${PORT_SSH}" | tee -a $LOG_FILE
else
    # Corrected the typo in the tee command
    echo " 🔐 SSH:  ssh ${USERNAME}@${IP} -p ${PORT_SSH}" | tee -a $LOG_FILE
    echo " 🧾 Login: ${USERNAME} / ${PASSWORD}" | tee -a $LOG_FILE
fi
echo "================================================"

# Keep container running
tail -f /dev/null
