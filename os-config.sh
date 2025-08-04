#!/bin/bash
set -e

# Configuration variables
OS_DIR="/opt/qemu"
IMG="${OS_DIR}/${OS_TYPE}.img"
SEED="${OS_DIR}/seed.iso"
LOG_FILE="/var/log/vm-startup.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

log "Starting OS configuration for $OS_TYPE..."

# Create directory if it doesn't exist
mkdir -p "$OS_DIR"

# Common configuration for Linux VMs (cloud-init seed)
if [ "$OS_TYPE" != "windows7" ] && [ "$OS_TYPE" != "windows10" ] && [ "$OS_TYPE" != "windows2022" ]; then
    log "Creating cloud-init seed ISO for Linux..."
    if [ ! -f "$SEED" ]; then
        # This user-data file configures a root user with a password
        cat <<EOF > /tmp/user-data
#cloud-config
password: root
chpasswd: { expire: False }
ssh_pwauth: True
EOF
        genisoimage -output "$SEED" -volid cidata -joliet -rock /tmp/user-data
        log "Cloud-init ISO created successfully."
    else
        log "Cloud-init ISO already exists, skipping."
    fi
fi

# Download VM image based on OS type
case "$OS_TYPE" in
    debian12)
        IMG_URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
        ;;
    ubuntu2204)
        IMG_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
        ;;
    windows10)
        # Using a publicly available Windows 10 Cloud Base image.
        # This URL is just an example; you may need to find an appropriate image source.
        # This URL will fail, as there are no free windows images. You must provide your own image.
        IMG_URL=""
        if [ -z "$IMG_URL" ]; then
            log "Error: Windows image URL is not defined. Please provide a valid URL."
            exit 1
        fi
        VIRTIO_URL="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"
        if [ ! -f "${OS_DIR}/virtio-win.iso" ]; then
            log "Downloading virtio drivers..."
            wget -O "${OS_DIR}/virtio-win.iso" "$VIRTIO_URL"
        else
            log "Virtio drivers already exist, skipping download."
        fi
        ;;
    *)
        log "Error: Unknown OS type '$OS_TYPE'. Exiting."
        exit 1
        ;;
esac

# Download the main VM image if it doesn't exist
if [ ! -f "$IMG" ]; then
    log "Downloading VM image for $OS_TYPE from $IMG_URL..."
    # Use wget with progress reporting to avoid silent hanging
    wget -O "$IMG" "$IMG_URL"
    if [ $? -ne 0 ]; then
        log "Error: Failed to download VM image from $IMG_URL"
        exit 1
    fi
    log "VM image downloaded successfully."
else
    log "VM image already exists at $IMG, skipping download."
fi

log "OS configuration complete."
