#!/bin/bash

# Script is invoked periodically by Kubernetes CronJob to create a "golden" template VM.

set -euo pipefail

# We SSH immediately, without checking host key...
echo "Preparing SSH config, agent, keys" >&2
mkdir -p ~/.ssh
cat <<EOF >~/.ssh/config
Host *
  StrictHostKeyChecking no
  ConnectTimeout 600
EOF
chmod 600 ~/.ssh/config

# Prepare SSH key for VM (dynamically) & add identity to SSH agent
ssh-keygen -t ed25519 -f id_ed25519 -N "" -q -C "Ephemeral Kubevirt VM for Golden Creator ssh-key"
eval $(ssh-agent -s)
ssh-add <(cat id_ed25519)

echo "Creating golden-vm" >&2

kubectl apply -f - <<EOF
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: golden-vm
  namespace: gitlab-runner
spec:
  runStrategy: Always
  dataVolumeTemplates:
    - metadata:
        creationTimestamp: null
        name: golden-vm
      spec:
        pvc:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: "15Gi"
          storageClassName: ceph-rbd
        source:
          registry:
            url: docker://quay.io/containerdisks/debian:13
  template:
    metadata:
      labels:
        gitlab-runner-pipeline: untrusted
    spec:
      terminationGracePeriodSeconds: 180
      domain:
        resources:
          requests:
            memory: '6Gi'
            cpu: 4
        devices:
          disks:
            - name: dv-containerdisk
              disk:
                bus: virtio
            - name: cloudinitdisk
              disk:
                bus: virtio
      volumes:
        - name: dv-containerdisk
          dataVolume:
            name: golden-vm
        - name: cloudinitdisk
          cloudInitNoCloud:
            userData: |
              #cloud-config
              ssh_authorized_keys:
                - "$(cat id_ed25519.pub)"
              packages:
                - git
              runcmd:
                # See GitLab troubleshooting (causes exit code 1 at prepare stage)
                - rm -f ~/.bash_logout /home/debian/.bash_logout

                # Just update packages
                - sudo apt-get update && sudo apt-get full-upgrade

                # Official docs to install docker
                - sudo apt-get update
                - sudo apt-get install ca-certificates curl
                - sudo install -m 0755 -d /etc/apt/keyrings
                - sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
                - sudo chmod a+r /etc/apt/keyrings/docker.asc
                - |
                  echo \
                    "deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \$(. /etc/os-release && echo "\$VERSION_CODENAME") stable" | \
                    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
                - sudo apt-get update
                - sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
                # "Rootless" docker
                - sudo groupadd docker
                - sudo usermod -aG docker debian
                - newgrp docker

                # Official docs to install gitlab-runner
                - curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" | sudo bash
                - sudo apt-get install -y gitlab-runner
EOF

echo "Waiting until Virtual Machine golden-vm is ready" >&2
kubectl wait -n gitlab-runner --for=condition=Ready "vm/golden-vm" --timeout 5m
echo "Virtual machine marked as ready, waiting until cloud-init target reached!" >&2
virtctl ssh "debian@vm/golden-vm" -c 'sudo cloud-init status --wait'

echo "Virtual machine ready, stopping!" >&2

kubectl patch -n gitlab-runner vm golden-vm --type merge -p '{"spec": {"runStrategy": "Halted"}}'
kubectl wait -n gitlab-runner --for=delete "vmi/golden-vm" --timeout 5m

echo "Virtual machine fully stopped. Taking snapshot" >&2

kubectl replace --force -f - <<EOF
apiVersion: snapshot.kubevirt.io/v1beta1
kind: VirtualMachineSnapshot
metadata:
  name: snap-golden-vm
  namespace: gitlab-runner
spec:
  source:
    apiGroup: kubevirt.io
    kind: VirtualMachine
    name: golden-vm
EOF

echo "Waiting for snapshot to be ready..." >&2
kubectl wait vmsnapshot snap-golden-vm -n gitlab-runner --for=condition=Ready --timeout=5m

echo "Snapshot created! Cleaning up VM and exiting" >&2
kubectl delete -n gitlab-runner vm golden-vm
