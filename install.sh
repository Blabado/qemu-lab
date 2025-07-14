#!/bin/bash



./create-infra-base.sh
./create-vm-from-template.sh infra-docker
./create-vm-from-template.sh infra-monitor
./create-vm-from-template.sh infra-ci
./create-vm-from-template.sh infra-storage
./create-vm-from-template.sh infra-gw
