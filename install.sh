#!/usr/bin/env bash
#set -x 
check_programs() {
    echo "Checking required programs..."
    local programs=("qemu-aarch64" "virsh" "mkisofs" "virt-install")
    local missing=()

    for program in "${programs[@]}"; do
        if ! which "$program" > /dev/null; then
            echo "$program not found"
            missing+=("$program")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo "Please install the missing programs: ${missing[*]}"
        exit 1
    else
        echo "All required programs are installed"
    fi
}

generate_ssh_key() {
    echo "Generating SSH keys for Ansible...."
    mkdir -p ./ssh_cloud
    cd ssh_cloud
    ssh-keygen -t ed25519 -f ./id_ed25519 -N ""
    cd ..
}

export_default_net() {
    sudo virsh net-define default.xml
    sudo virsh net-autostart default
    sudo virsh net-start default

}

check_programs

echo "Do you want to configure an ssh key? [n/Y]"
read answer
answer=${answer:-y}

if [[ "$answer" == "y" ]]; then    
    generate_ssh_key
fi

export_default_net
./create-infra-base.sh
#./create-infra-base.sh test1
#./create-vm-from-template.sh infra-docker
#./create-vm-from-template.sh infra-monitor
#./create-vm-from-template.sh infra-ci
#./create-vm-from-template.sh infra-storage
#./create-vm-from-template.sh infra-gw
