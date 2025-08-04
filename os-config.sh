#!/bin/bash
set -e

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> /var/log/os-config.log
}

mkdir -p /var/log
> /var/log/os-config.log

# Default cloud-init user-data
create_user_data() {
    printf "#cloud-config\n\
users:\n\
  - name: root\n\
    plain_text_passwd: root\n\
    lock_passwd: false\n\
    sudo: ALL=(ALL) NOPASSWD:ALL\n\
chpasswd:\n\
  list: |\n\
    root:root\n\
  expire: false\n\
ssh_pwauth: true\n\
runcmd:\n\
  - sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config\n\
  - sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config\n\
  - systemctl restart ssh\n" > /cloud-init/user-data
}

# Desktop-specific cloud-init configuration
create_desktop_user_data() {
    local desktop_pkg="$1"
    printf "#cloud-config\n\
users:\n\
  - name: root\n\
    plain_text_passwd: root\n\
    lock_passwd: false\n\
    sudo: ALL=(ALL) NOPASSWD:ALL\n\
chpasswd:\n\
  list: |\n\
    root:root\n\
  expire: false\n\
ssh_pwauth: true\n\
packages:\n\
  - $desktop_pkg\n\
runcmd:\n\
  - sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config\n\
  - sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config\n\
  - systemctl enable --now $desktop_pkg\n\
  - systemctl restart ssh\n" > /cloud-init/user-data
}

# Create cloud-init metadata
echo "instance-id: vm-$OS_TYPE\nlocal-hostname: vm-$OS_TYPE" > /cloud-init/meta-data

# Download and configure OS image
case "$OS_TYPE" in
    debian10)
        log "Downloading Debian 10 cloud image..."
        curl -L https://cloud.debian.org/images/cloud/buster/latest/debian-10-genericcloud-amd64.qcow2 -o /opt/qemu/debian.img
        create_user_data
        ;;
    debian11)
        log "Downloading Debian 11 cloud image..."
        curl -L https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-genericcloud-amd64.qcow2 -o /opt/qemu/debian.img
        create_user_data
        ;;
    debian12)
        log "Downloading Debian 12 cloud image..."
        curl -L https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2 -o /opt/qemu/debian.img
        create_user_data
        ;;
    debian13)
        log "Note: Debian 13 may not be released yet. Using latest available testing image..."
        curl -L https://cloud.debian.org/images/cloud/trixie/daily/latest/debian-trixie-genericcloud-amd64.qcow2 -o /opt/qemu/debian.img
        create_user_data
        ;;
    fedora40)
        log "Downloading Fedora 40 cloud image..."
        curl -L https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-40-1.14.x86_64.qcow2 -o /opt/qemu/fedora.img
        create_user_data
        ;;
    ubuntu18)
        log "Downloading Ubuntu 18.04 cloud image..."
        curl -L https://cloud-images.ubuntu.com/bionic/current/bionic-server-cloudimg-amd64.img -o /opt/qemu/ubuntu.img
        create_user_data
        ;;
    ubuntu20)
        log "Downloading Ubuntu 20.04 cloud image..."
        curl -L https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img -o /opt/qemu/ubuntu.img
        create_user_data
        ;;
    ubuntu22)
        log "Downloading Ubuntu 22.04 cloud image..."
        curl -L https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img -o /opt/qemu/ubuntu.img
        create_user_data
        ;;
    ubuntu24)
        log "Downloading Ubuntu 24.04 cloud image..."
        curl -L https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img -o /opt/qemu/ubuntu.img
        create_user_data
        ;;
    arch)
        log "Downloading Arch Linux cloud image (community-maintained)..."
        curl -L https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2 -o /opt/qemu/arch.img
        create_user_data
        ;;
    rocky)
        log "Downloading Rocky Linux 9 cloud image..."
        curl -L https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2 -o /opt/qemu/rocky.img
        create_user_data
        ;;
    alma)
        log "Downloading AlmaLinux 9 cloud image..."
        curl -L https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2 -o /opt/qemu/alma.img
        create_user_data
        ;;
    alpine)
        log "Alpine Linux cloud images are not officially available. Using minimal setup..."
        curl -L https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/x86_64/alpine-standard-3.20.3-x86_64.iso -o /opt/qemu/alpine.iso
        create_user_data
        ;;
    kali)
        log "Downloading Kali Linux cloud image..."
        curl -L https://cloud.kali.org/images/kali-linux-2024.3-cloud-amd64.qcow2 -o /opt/qemu/kali.img
        create_user_data
        ;;
    debian12-desktop)
        log "Downloading Debian 12 cloud image for desktop..."
        curl -L https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2 -o /opt/qemu/debian.img
        create_desktop_user_data "xfce4"
        ;;
    ubuntu24-desktop)
        log "Downloading Ubuntu 24.04 cloud image for desktop..."
        curl -L https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img -o /opt/qemu/ubuntu.img
        create_desktop_user_data "ubuntu-desktop"
        ;;
    windows7|windows10|windows2022)
        log "Windows images must be prebuilt and placed in /opt/qemu/windows.img"
        # Assume prebuilt QCOW2 image is provided
        if [ ! -f /opt/qemu/windows.img ]; then
            log "Error: Windows image not found at /opt/qemu/windows.img"
            exit 1
        fi
        # No cloud-init for Windows
        # We need to create dummy cloud-init files so genisoimage doesn't fail.
        touch /cloud-init/user-data /cloud-init/meta-data
        ;;
    redstar)
        log "Red Star OS image must be prebuilt and placed in /opt/qemu/redstar.img"
        if [ ! -f /opt/qemu/redstar.img ]; then
            log "Error: Red Star OS image not found at /opt/qemu/redstar.img"
            exit 1
        fi
        # No cloud-init for Red Star OS
        touch /cloud-init/user-data /cloud-init/meta-data
        ;;
    shell)
        log "Shell mode selected. No VM will be started."
        exit 0
        ;;
    *)
        log "Error: Unsupported OS_TYPE: $OS_TYPE"
        exit 1
        ;;
esac

# Create cloud-init ISO for Linux-based OSes
if [ "$OS_TYPE" != "windows7" ] && [ "$OS_TYPE" != "windows10" ] && [ "$OS_TYPE" != "windows2022" ] && [ "$OS_TYPE" != "redstar" ] && [ "$OS_TYPE" != "shell" ]; then
    genisoimage -output /opt/qemu/seed.iso -volid cidata -joliet -rock /cloud-init/user-data /cloud-init/meta-data
fi

log "OS configuration completed for $OS_TYPE"
