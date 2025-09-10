#!/bin/bash

set -euo pipefail

_vm_name() {
  printf 'runner-%s-project-%d-pipeline-%d-job-%d' "${CUSTOM_ENV_CI_PROJECT_ID}" "${CUSTOM_ENV_CI_PIPELINE_IID}" "${CUSTOM_ENV_CI_JOB_ID}"
}

config() {
  echo "Loading ephemeral SSH key" >&2
  key_file=$(mktemp -u)
  ssh-keygen -t ed25519 -f "$key_file" -N "" -q -C "Ephemeral Kubevirt VM for GitLab runner ssh-key"

  echo "Feeding configuration output to GitLab runner controller" >&2
  cat <<EOS
{
  "builds_dir": "/home/debian/builds/${CUSTOM_ENV_CI_CONCURRENT_PROJECT_ID}/${CUSTOM_ENV_CI_PROJECT_PATH_SLUG}",
  "cache_dir": "/home/debian/cache/${CUSTOM_ENV_CI_CONCURRENT_PROJECT_ID}/${CUSTOM_ENV_CI_PROJECT_PATH_SLUG}",
  "builds_dir_is_shared": false,
  "hostname": "$(_vm_name)",
  "driver": {
    "name": "kubevirt driver",
    "version": "v0.0.1"
  },
  "job_env" : {
    "GITLAB_KUBEVIRT_SSH_PRIVATE_KEY": "$(cat $key_file | base64 -w0)",
    "GITLAB_KUBEVIRT_SSH_PUB_KEY": "$(cat "$key_file.pub")"
  },
  "shell": "bash"
}
EOS
}

prepare() {
  echo "Loading ephemeral ssh key: ${GITLAB_KUBEVIRT_SSH_PUB_KEY}" >&2

  echo "Creating VirtualMachineInstance $(_vm_name) in Kubernetes" >&2

  # We SSH immediately, without checking host key...
  mkdir -p ~/.ssh
  cat <<EOF >~/.ssh/config
Host *
  StrictHostKeyChecking no
EOF
  chmod 600 ~/.ssh/config

  kubectl apply -f - <<EOF
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: "$(_vm_name)"
  namespace: gitlab-runner
spec:
  runStrategy: Always
  template:
    spec:
      terminationGracePeriodSeconds: 180
      domain:
        resources:
          requests:
            memory: '6Gi'
            cpu: 4
        devices:
          disks:
            - name: containerdisk
              disk:
                bus: virtio
            - name: cloudinitdisk
              disk:
                bus: virtio
      volumes:
        - name: containerdisk
          containerDisk:
            image: quay.io/containerdisks/debian:13
        - name: cloudinitdisk
          cloudInitNoCloud:

            # Cilium, be it a blessing or a curse, does not support VM network traffic to KubeDNS or any other cluster-related networks.
            # If it worked, we could secure it with some NetworkPolicies, but as is, we only need to worry about DNS and not using KubeDNS.
            networkData: |
              version: 2
              ethernets:
                all:
                  match:
                    name: "*"
                  dhcp4: true
                  dhcp4-overrides:
                    use-dns: false
                    use-domains: false
                  nameservers:
                    addresses:
                      - 1.1.1.1
                      - 8.8.8.8
            userData: |
              #cloud-config
              ssh_authorized_keys:
                - "${GITLAB_KUBEVIRT_SSH_PUB_KEY}"
                - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP6ylVtPMpT5OxsghEYjZXPadVvlgxJK7P0J3wfy0C0x jaqxues@gpg
              packages:
                - git
              runcmd:
                # See GitLab troubleshooting (causes exit code 1 at prepare stage)
                - rm -f ~/.bash_logout /home/debian/.bash_logout
                - sudo apt-get update

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

  echo "Waiting until Virtual Machine $(_vm_name) is ready" >&2

  kubectl wait --for=condition=Ready "vm/$(_vm_name)" --timeout 5m

  echo "Virtual machine marked as ready, waiting until cloud-init target reached!" >&2

  eval $(ssh-agent -s)
  ssh-add <(echo $GITLAB_KUBEVIRT_SSH_PRIVATE_KEY | base64 -d)

  virtctl ssh "debian@vm/$(_vm_name)" -c 'sudo cloud-init status --wait'
}

run() {
  echo "Run stage, adding temporary ssh-key to agent"
  eval $(ssh-agent -s)
  ssh-add <(echo $GITLAB_KUBEVIRT_SSH_PRIVATE_KEY | base64 -d)
  echo "Running scripts over kubectl virt ssh"
  virtctl ssh "debian@vm/$(_vm_name)" -c 'bash' <"${1}"
}

cleanup() {
  echo "Cleaning up virtual machine $(_vm_name)" >&2
  kubectl delete vm "$(_vm_name)"
}

case "${1:-}" in
config)
  echo "Executor running config stage" >&2
  config
  ;;
prepare)
  echo "Executor running prepare stage" >&2
  prepare
  ;;
run)
  echo "Executor running run stage" >&2
  run "${2}" "${3}"
  ;;
cleanup)
  echo "Executor running cleanup stage" >&2
  cleanup
  ;;
*)
  echo "Error invalid command ${1:-}"
  exit 1
  ;;
esac
