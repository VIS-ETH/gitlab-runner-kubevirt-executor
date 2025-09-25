#!/bin/bash

# This is called by the GitLab runner, when a Job needs to be run

set -euo pipefail

_vm_name() {
  printf 'runner-%s-project-%d-pipeline-%d-job-%d' "${CUSTOM_ENV_CI_PROJECT_ID}" "${CUSTOM_ENV_CI_PIPELINE_IID}" "${CUSTOM_ENV_CI_JOB_ID}"
}

config() {
  echo "Loading ephemeral SSH key" >&2
  SSH_PRIVATE_KEY="$(kubectl get secret kubevirt-rotating-master-ssh-priv-key -o=jsonpath='{.data.master-key}')"

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
    "GITLAB_KUBEVIRT_SSH_PRIVATE_KEY": "${SSH_PRIVATE_KEY}"
  },
  "shell": "bash"
}
EOS
}

prepare() {
  echo "Creating VirtualMachineInstance $(_vm_name) in Kubernetes" >&2

  # We SSH immediately, without checking host key...
  mkdir -p ~/.ssh
  cat <<EOF >~/.ssh/config
Host *
  StrictHostKeyChecking no
EOF
  chmod 600 ~/.ssh/config

  # No need to wait until snapshot ready, just wait until clone is ready.
  kubectl apply -f - <<EOF
kind: VirtualMachineClone
apiVersion: "clone.kubevirt.io/v1beta1"
metadata:
  name: clone-golden-to-$(_vm_name)
  namespace: gitlab-runner
spec:
  source:
    apiGroup: kubevirt.io
    kind: VirtualMachineSnapshot
    name: snap-golden-vm
  target:
    apiGroup: kubevirt.io
    kind: VirtualMachine
    name: $(_vm_name)
EOF
  echo "Waiting until cloning finished" >&2
  kubectl wait -n gitlab-runner vmclone clone-golden-to-$(_vm_name) --for=condition=Ready --timeout=5m

  echo "Clone ready, deleting clone object and patching & starting VM" >&2
  kubectl delete -n gitlab-runner vmclone clone-golden-to-$(_vm_name)

  # This label is used in network policies
  kubectl patch -n gitlab-runner vm $(_vm_name) --type merge -p '{"spec": {"template": {"metadata": {"labels": {"gitlab-runner-pipeline": "untrusted"}}}}}'

  kubectl patch -n gitlab-runner vm $(_vm_name) --type merge -p '{"spec": {"runStrategy": "Always"}}'

  echo "Waiting until Virtual Machine $(_vm_name) is ready" >&2
  kubectl wait --for=condition=Ready "vm/$(_vm_name)" --timeout 10m
  echo "Virtual machine marked as ready, waiting until cloud-init target reached!" >&2

  eval $(ssh-agent -s)
  ssh-add <(echo $GITLAB_KUBEVIRT_SSH_PRIVATE_KEY | base64 -d)

  for i in 1 2 3 4 5; do
    { virtctl ssh "debian@vm/$(_vm_name)" -c 'sudo cloud-init status --wait' && break; } || sleep 30
  done
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
  kubectl delete -n gitlab-runner vm "$(_vm_name)"
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
