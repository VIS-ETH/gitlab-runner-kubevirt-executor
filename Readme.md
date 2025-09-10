# Kubevirt executor for GitLab Runners

So, before we get into this, yes I know, this is overcomplicating things. We could care less about security, make things easier, or just accept that docker-in-docker is impossible in GitLab CI/CD. At the time of writing, Kaniko was just archived by Google, and all other solutions (buildah, buildkit daemonless etc) still are not a true replacement, as they require some configuration (apparmor profile unconfined). Docker-in-docker is essentially pain by design, requiring privileged containers etc.

GitLab executors are incredibly easy to implement, and coupling VMs with Kubernetes and throwing a GitLab runner at it was more of a funny thought than anything else. But... it works phenomenally well.

## Workflow

In order to avoid a GitLab runner requiring a docker image built by a GitLab runner, get your push-secret to the VSETH GCR and push the locally built images directly. This also saves a lot of time, as it is much faster. Put the secret at `.config/config.json` in this repository. Run make to automatically build the image and push it. Restart the GitLab runner as required, and you can essentially instantly retry a failed job, which makes for a very efficient workflow.
