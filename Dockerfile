# Use Debian 12 as the base image for the container
FROM debian:12

# Set non-interactive frontend to avoid prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install core dependencies for QEMU, noVNC, SSH, and cloud-init
RUN apt-get update && apt-get install -y --no-install-recommends \
    qemu-system-x86 \
    qemu-system-gui \
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
    whois \
    sshpass \
    && rm -rf /var/lib/apt/lists/*

# Create required directories
RUN mkdir -p /data /novnc /opt/qemu /cloud-init

# Copy scripts and configuration
COPY start.sh /start.sh
COPY os-config.sh /os-config.sh

# Ensure scripts have Unix line endings and are executable
RUN dos2unix /start.sh /os-config.sh && \
    chmod +x /start.sh /os-config.sh
    
# NOTE: The following line is removed. We don't want to run the scripts during build time.
# /bin/bash -n /start.sh /os-config.sh

# Expose ports for noVNC (6080) and SSH (2221)
EXPOSE 6080 2221

# Mount volume for VM disk
VOLUME /data

# Set environment variable for OS type (default to debian12)
ARG OS_TYPE=debian12
ENV OS_TYPE=${OS_TYPE}
ENV DESKTOP=false
ENV SHELL_MODE=false

# NOTE: This is the second key change. We are removing this RUN command.
# RUN /bin/bash /os-config.sh

# Set the command to run when the container starts.
# The start.sh script will be responsible for calling os-config.sh and then the VM.
CMD ["/bin/bash", "/start.sh"]
