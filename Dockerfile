FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

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
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /data /novnc /opt/qemu /cloud-init

# Ubuntu cloud image
RUN curl -L https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img \
    -o /opt/qemu/ubuntu.qcow2

# cloud-init meta-data
RUN echo "instance-id: ubuntu-vm\nlocal-hostname: ubuntu-vm" > /cloud-init/meta-data

# cloud-init user-data
RUN cat <<'EOF' > /cloud-init/user-data
#cloud-config
hostname: ubuntu-vm
users:
  - name: root
    shell: /bin/bash
    lock_passwd: false
    passwd: root
    sudo: ALL=(ALL) NOPASSWD:ALL
ssh_pwauth: true
disable_root: false
chpasswd:
  expire: false
runcmd:
  - systemctl enable ssh
  - systemctl restart ssh
EOF

RUN genisoimage -output /opt/qemu/seed.iso -volid cidata -joliet -rock \
    /cloud-init/user-data /cloud-init/meta-data

# noVNC
RUN curl -L https://github.com/novnc/noVNC/archive/refs/tags/v1.3.0.zip -o /tmp/novnc.zip && \
    unzip /tmp/novnc.zip -d /tmp && \
    mv /tmp/noVNC-1.3.0/* /novnc && \
    rm -rf /tmp/*

# start script
RUN cat <<'EOF' > /start.sh
#!/bin/bash
set -e

DISK="/data/vm.qcow2"
BASE="/opt/qemu/ubuntu.qcow2"
SEED="/opt/qemu/seed.iso"

if [ ! -f "$DISK" ]; then
  echo "Creating disk..."
  qemu-img create -f qcow2 -b "$BASE" "$DISK" 40G
fi

qemu-system-x86_64 \
  -machine accel=tcg \
  -cpu qemu64 \
  -smp 4 \
  -m 32048 \
  -drive file="$DISK",if=virtio \
  -drive file="$SEED",media=cdrom \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  -device virtio-net,netdev=net0 \
  -vga virtio \
  -display vnc=:0 &

websockify --web=/novnc 6080 localhost:5900 &

echo "===================================="
echo "VNC  : http://localhost:6080/vnc.html"
echo "SSH  : ssh root@localhost -p 2222"
echo "LOGIN: root / root"
echo "===================================="

tail -f /dev/null
EOF

RUN chmod +x /start.sh

VOLUME /data
EXPOSE 6080 2222

CMD ["/start.sh"]
