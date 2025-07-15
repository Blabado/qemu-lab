#set -x
#-------------NAMES---------------------
ADMINNAME="sys_admin"
BASE_NAME="infra_docker"
VM_NAME="${1:-$BASE_NAME}"
#-------------DIR-----------------------
BASE_DIR="$HOME/qemu-lab"
IMAGE_DIR="$BASE_DIR/cloud-images"
DISK_DIR="$BASE_DIR/pool"
CI_DIR="$BASE_DIR/cloud-init/$VM_NAME"
#--------------IMG----------------------
SEED_ISO="$CI_DIR/seed-$VM_NAME.iso"
CLOUD_IMG="$IMAGE_DIR/jammy-server-cloudimg-amd64.img"
#-------------DISK----------------------
DISK="$DISK_DIR/${VM_NAME}.qcow2"
BASE_DISK="$DISK_DIR/${BASE_NAME}.qcow2"
#------------ SSH-----------------------
SSH_KEY_PATH_PUB="ssh_cloud/id_ed25519.pub"
SSH_KEY_PATH_PRIV="ssh_cloud/id_ed25519"
SSH_KEY=$(cat "$SSH_KEY_PATH_PUB")

#----------------General----------------
echo "[1/6] Create directory..."
mkdir -p "$IMAGE_DIR" "$DISK_DIR" "$CI_DIR"

echo "[2/6] Download cloud-image (if none)..."
if [ ! -f "$CLOUD_IMG" ]; then
    wget -O "$CLOUD_IMG" https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
fi

echo "[3/6] Preparing cloud-init..."
cat > "$CI_DIR/user-data" <<EOF
#cloud-config
hostname: $VM_NAME
users:
  - name: $ADMINNAME
    groups: [sudo]
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    ssh_authorized_keys:
      - $SSH_KEY
disable_root: true
package_update: true
package_upgrade: true
packages:
  - qemu-guest-agent
runcmd:
  - [ systemctl, enable, qemu-guest-agent ]
  - [ systemctl, start, qemu-guest-agent ]
EOF

cat > "$CI_DIR/meta-data" <<EOF
instance-id: $VM_NAME
local-hostname: $VM_NAME
EOF

echo "[4/6] Генерация seed ISO..."
mkisofs -output "$SEED_ISO" -volid cidata -joliet -rock \
    "$CI_DIR/user-data" "$CI_DIR/meta-data"


if [ "$VM_NAME" = "infra_docker" ]; then
    echo "[5/6] Создание QCOW2-диска на базе cloud image..."
    qemu-img create -f qcow2 -F qcow2 -b "$CLOUD_IMG" "$DISK" 10G
else
    echo "[5/6] Клонирование диска..."
    cp "$BASE_DISK" "$DISK"  
fi

echo "[6/6] Запуск virt-install..."
virt-install \
  --connect qemu:///session \
  --name "$VM_NAME" \
  --ram 2048 \
  --vcpus 2 \
  --os-variant ubuntu22.04 \
  --disk path="$DISK",format=qcow2 \
  --disk path="$SEED_ISO",device=cdrom \
  --network bridge=virbr0 \
  --import \
  --noautoconsole

echo "VM '$VM_NAME' создана и запущена!"

echo "Ожидаем получения IP-адреса..."

sleep 4  # даём немного времени на init infra-base

echo "[INFO] Получение IP-адреса VM '$VM_NAME'..."
for i in {1..15}; do
  VM_IP=$(virsh domifaddr --source arp "$VM_NAME" | awk '/ipv4/ {print $4}' | cut -d'/' -f1)
  if [ -n "$VM_IP" ]; then
    echo "[INFO] IP: $VM_IP"
    break
  fi
  echo "[INFO] Ожидаем появления IP-адреса..."
  sleep 4
done

if [ -z "$VM_IP" ]; then
  echo "[ERROR] Не удалось получить IP-адрес"
  exit 1
fi

echo "[INFO] Ожидаем доступности SSH от $ADMINNAME@$VM_IP..."

MAX_ATTEMPTS=30
SSH_CMD="ssh -i $SSH_KEY_PATH_PRIV -o StrictHostKeyChecking=no -o ConnectTimeout=3"

for ((i=1; i<=MAX_ATTEMPTS; i++)); do
  $SSH_CMD "$ADMINNAME@$VM_IP" "echo ok" &>/dev/null && break
  echo "[WAIT] Попытка $i/$MAX_ATTEMPTS: SSH ещё недоступен..."
  sleep 5
done

if (( i > MAX_ATTEMPTS )); then
  echo "[ERROR] SSH не стал доступен после $MAX_ATTEMPTS попыток"
  exit 1
else
  echo "[SUCCESS] SSH доступен!"
fi

echo "[INFO] Проверка завершения cloud-init..."
for i in {1..20}; do
  CLOUD_INIT_DONE=$(ssh -i $SSH_KEY_PATH_PRIV "$ADMINNAME@$VM_IP" "cloud-init status --wait 2>/dev/null")
  if [[ "$CLOUD_INIT_DONE" == *"done"* ]]; then
    echo "[INFO] Cloud-init завершён ✅"
    exit
  fi
    echo "[INFO] Cloud-init ещё работает..."
    sleep 5
  done

echo "[WARNING] Не удалось дождаться завершения cloud-init"
