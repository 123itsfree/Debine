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
    net-tools \
    netcat-openbsd \
    sudo \
    bash \
    && rm -rf /var/lib/apt/lists/*

# Create required directories
RUN mkdir -p /data /novnc /opt/qemu /cloud-init

# Download Debian 12 cloud image
RUN curl -L https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2 \
    -o /opt/qemu/debian.img

# Create cloud-init metadata
RUN echo "instance-id: debian-vm\nlocal-hostname: debian-vm" > /cloud-init/meta-data

# Create cloud-init user-data
RUN printf "#cloud-config\npreserve_hostname: false\nhostname: debian-vm\nusers:\n  - name: root\n    gecos: root\n    shell: /bin/bash\n    lock_passwd: false\n    passwd: \$6\$abcd1234\$W6wzBuvyE.D1mBGAgQw2uvUO/honRrnAGjFhMXSk0LUbZosYtoHy1tUtYhKlALqIldOGPrYnhSrOfAknpm91i0\n    sudo: ALL=(ALL) NOPASSWD:ALL\ndisable_root: false\nssh_pwauth: true\nchpasswd:\n  list: |\n    root:root\n  expire: false\nruncmd:\n  - systemctl enable ssh\n  - systemctl restart ssh\n" > /cloud-init/user-data

# Create cloud-init ISO
RUN genisoimage -output /opt/qemu/seed.iso -volid cidata -joliet -rock /cloud-init/user-data /cloud-init/meta-data

# Setup noVNC
RUN curl -L https://github.com/novnc/noVNC/archive/refs/tags/v1.3.0.zip -o /tmp/novnc.zip && \
    unzip /tmp/novnc.zip -d /tmp && \
    mv /tmp/noVNC-1.3.0/* /novnc && \
    rm -rf /tmp/novnc.zip /tmp/noVNC-1.3.0

# Add start script
RUN echo '#!/bin/bash' > /start.sh && \
    echo 'set -e' >> /start.sh && \
    echo '' >> /start.sh && \
    echo 'DISK="/data/vm.raw"' >> /start.sh && \
    echo 'IMG="/opt/qemu/debian.img"' >> /start.sh && \
    echo 'SEED="/opt/qemu/seed.iso"' >> /start.sh && \
    echo '' >> /start.sh && \
    echo 'if [ ! -f "$DISK" ]; then' >> /start.sh && \
    echo '    echo "Creating VM disk..."' >> /start.sh && \
    echo '    qemu-img convert -f qcow2 -O raw "$IMG" "$DISK"' >> /start.sh && \
    echo '    qemu-img resize "$DISK" 50G' >> /start.sh && \
    echo 'fi' >> /start.sh && \
    echo '' >> /start.sh && \
    echo 'qemu-system-x86_64 \\' >> /start.sh && \
    echo '    -enable-kvm \\' >> /start.sh && \
    echo '    -cpu host \\' >> /start.sh && \
    echo '    -smp 2 \\' >> /start.sh && \
    echo '    -m 6144 \\' >> /start.sh && \
    echo '    -drive file="$DISK",format=raw,if=virtio \\' >> /start.sh && \
    echo '    -drive file="$SEED",format=raw,if=virtio \\' >> /start.sh && \
    echo '    -netdev user,id=net0,hostfwd=tcp::2221-:22 \\' >> /start.sh && \
    echo '    -device virtio-net,netdev=net0 \\' >> /start.sh && \
    echo '    -vga virtio \\' >> /start.sh && \
    echo '    -display vnc=:0 \\' >> /start.sh && \
    echo '    -daemonize' >> /start.sh && \
    echo '' >> /start.sh && \
    echo 'websockify --web=/novnc 6080 localhost:5900 &' >> /start.sh && \
    echo '' >> /start.sh && \
    echo 'echo "================================================"' >> /start.sh && \
    echo 'echo " 🖥️  VNC: http://localhost:6080/vnc.html"' >> /start.sh && \
    echo 'echo " 🔐 SSH: ssh root@localhost -p 2221"' >> /start.sh && \
    echo 'echo " 🧾 Login: root / root"' >> /start.sh && \
    echo 'echo "================================================"' >> /start.sh && \
    echo '' >> /start.sh && \
    echo 'for i in {1..30}; do' >> /start.sh && \
    echo '  nc -z localhost 2221 && echo "✅ VM is ready!" && break' >> /start.sh && \
    echo '  echo "⏳ Waiting for SSH..."' >> /start.sh && \
    echo '  sleep 2' >> /start.sh && \
    echo 'done' >> /start.sh && \
    echo '' >> /start.sh && \
    echo 'wait' >> /start.sh

RUN chmod +x /start.sh

# Expose ports
EXPOSE 6080 2221

# Mount volume for VM disk
VOLUME /data

# Entry point
CMD ["bash", "/start.sh"]
