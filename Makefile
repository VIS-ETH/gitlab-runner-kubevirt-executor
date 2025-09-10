.PHONY: docker-build-local
docker-build-local:
	docker build \
		-t eu.gcr.io/aerial-reef-202214/vseth/1100-fv/1116-vis/cit/kubevirt-gitlab-runner:local-build \
		-t eu.gcr.io/aerial-reef-202214/vseth/1100-fv/1116-vis/cit/kubevirt-gitlab-runner:$(git rev-parse --abbrev-ref HEAD) \
		.

.PHONY: docker-push
docker-push:
	DOCKER_CONFIG=./.config.json \
	  docker image push -a \
		eu.gcr.io/aerial-reef-202214/vseth/1100-fv/1116-vis/cit/kubevirt-gitlab-runner:local-build
