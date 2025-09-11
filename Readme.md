# Kubevirt executor for GitLab Runners

[TOC]

So, before we get into this, yes I know, this is overcomplicating things. We could care less about security, make things easier, or just accept that docker-in-docker is impossible in GitLab CI/CD. At the time of writing, Kaniko was just archived by Google, and all other solutions (buildah, buildkit daemonless etc) still are not a true replacement, as they require some configuration (apparmor profile unconfined). Docker-in-docker is essentially pain by design, requiring privileged containers etc.

GitLab executors are incredibly easy to implement, and coupling VMs with Kubernetes and throwing a GitLab runner at it was more of a funny thought than anything else. But... it works phenomenally well.

## Development Workflow

In order to avoid a GitLab runner requiring a docker image built by a GitLab runner, get your push-secret to the VSETH GCR and push the locally built images directly. This also saves a lot of time, as it is much faster. Put the secret at `.config/config.json` in this repository. Run make to automatically build the image and push it. Restart the GitLab runner as required, and you can essentially instantly retry a failed job, which makes for a very efficient workflow. The logs of the VM can be viewed via the `guest-logs` container in the respective pod watching and controlling the VM.

## GitLab runners explained

The GitLab runner does most work for you: collecting all the bash scripts that are required to run everything, handling logs, environment variables, secrets. The only responsibility is implementing 4 stages:

- config: Tell GitLab what "driver" (executor) is handling the Job, where to store the build cache, the build source, and so on. It can also pass environment variables to all other stages (but they are confidential and not shared with the Job itself).
- prepare: Get everything prepared for the GitLab job. Create a container, a VM, any place where code might run and wait until it can be used.
- run: This stage is called multiple times, but each time GitLab really only expects that the bash script it passes to you is run, be that via SSH, docker exec, kubectl exec or whatever else (easy).
- cleanup: Delete the environment if necessary or desired.

Nice example GitLab runners:

- Bash libvirtd example: <https://gitlab.archlinux.org/archlinux/infrastructure/-/blob/master/roles/gitlab_runner/files/libvirt-executor>
- Golang Kubevirt example: <https://github.com/Snaipe/gitlab-runner-kubevirt>
