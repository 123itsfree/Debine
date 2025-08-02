FROM debian:12

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    qemu-system-x86 \
    qemu-utils \
    cloud-image-utils \
    genisoimage \
    novnc \
    websockify \
    curl \
    unzip \
    openssh-client \
    openssh-server \
    net-tools \
    netcat-openbsd \
    sudo \
    bash \
    dos2unix \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Create required directories
RUN mkdir -p /data /novnc /opt/qemu /cloud-init

# Download Debian 12 cloud image
RUN curl -L https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2 \
    -o /opt/qemu/debian.img

# Create cloud-init metadata
RUN echo "instance-id: debian-vm\nlocal-hostname: debian-vm" > /cloud-init/meta-data

# Create cloud-init user-data
RUN printf "#cloud-config\npreserve_hostname: false\nhostname: debian-vm\nusers:\n  - name: root\n    gecos: root\n    shell: /bin/bash\n    lock_passwd: false\n    passwd: \$6\$abcd1234\$W6wzBuvyE.D1mBGAgQw2uvUO/honRrnAGjFhMXSk0LUbZosYtoHy1tUtYhKlALqIldOGPrYnhSrOfAknpm91i0\n    sudo: ALL=(ALL) NOPASSWD:ALL\ndisable_root: false\nssh_pwauth: true\nchpasswd:\n  list: |\n    root:root\n  expire: false\nruncmd:\n  - systemctl enable ssh\n  - systemctl start ssh\n" > /cloud-init/user-data

# Create cloud-init ISO
RUN genisoimage -output /opt/qemu/seed.iso -volid cidata -joliet -rock /cloud-init/user-data /cloud-init/meta-data

# Setup noVNC
RUN curl -L https://github.com/novnc/noVNC/archive/refs/tags/v1.3.0.zip -o /tmp/novnc.zip && \
    unzip /tmp/novnc.zip -d /tmp && \
    mv /tmp/noVNC-1.3.0/* /novnc && \
    rm -rf /tmp/novnc.zip /tmp/noVNC-1.3.0

# Create start.sh script
RUN cat <<'EOF' > /start.sh
#!/bin/bash
set -e

DISK="/data/vm.raw"
IMG="/opt/qemu/debian.img"
SEED="/opt/qemu/seed.iso"
PORT_SSH=2221
PORT_VNC=6080
USERNAME="root"
PASSWORD="root"

# Ensure script is executable
chmod +x /start.sh

# Check if KVM is available
if [ -e /dev/kvm ]; then
    KVM="--enable-kvm -cpu host"
else
    echo "⚠️ KVM not available, falling back to software emulation"
    KVM=""
fi

# Get public IP (fallback to localhost if failed)
IP=$(curl -s --connect-timeout 5 https://api.ipify.org || echo "localhost")

# Create VM disk if it doesn't exist
if [ ! -f "$DISK" ]; then
    echo "Creating VM disk..."
    qemu-img convert -f qcow2 -O raw "$IMG" "$DISK" || { echo "Failed to convert disk image"; exit 1; }
    qemu-img resize "$DISK" 50G || { echo "Failed to resize disk"; exit 1; }
fi

# Verify required files exist
if [ ! -f "$IMG" ] || [ ! -f "$SEED" ]; then
    echo "Error: Required files ($IMG or $SEED) are missing"
    exit 1
fi

# Start SSH server in container
mkdir -p /var/run/sshd
/usr/sbin/sshd

# Start noVNC
websockify --web=/novnc ${PORT_VNC} localhost:5900 &

# Start QEMU in foreground
qemu-system-x86_64 \
    $KVM \
    -smp 2 \
    -m 2048 \
    -drive file="$DISK",format=raw,if=virtio \
    -drive file="$SEED",format=raw,if=virtio \
    -netdev user,id=net0,hostfwd=tcp::${PORT_SSH}-:22 \
    -device virtio-net,netdev=net0 \
    -vga virtio \
    -display vnc=:0 &

# Wait for SSH to be available
for i in {1..30}; do
    nc -z localhost ${PORT_SSH} && echo "✅ VM is ready!" && break
    echo "⏳ Waiting for SSH..."
    sleep 2
done

echo "================================================"
echo " 🖥️  VNC:  http://${IP}:${PORT_VNC}/vnc.html"
echo " 🔐 SSH:  ssh ${USERNAME}@${IP} -p ${PORT_SSH}"
echo " 🧾 Login: ${USERNAME} / ${PASSWORD}"
echo "================================================"

# Keep container running
wait
EOF

# Ensure Unix line endings and make executable
RUN dos2unix /start.sh && chmod +x /start.sh && /bin/bash -n /start.sh

# Expose ports
EXPOSE 6080 2221

# Mount volume for VM disk
VOLUME /data

# Start the system with explicit Bash invocation
CMD ["/bin/bash", "/start.sh"]
