FROM registry.gitlab.com/gitlab-org/gitlab-runner:alpine-v18.3.1

WORKDIR /deps

RUN apk add curl \
  && curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
  && mv kubectl /bin/kubectl \
  && chmod 755 /bin/kubectl

RUN VERSION=$(curl https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt) \
  && curl -Lo virtctl https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/virtctl-${VERSION}-linux-amd64 \
  && mv virtctl /bin/virtctl \
  && chmod 755 /bin/virtctl

COPY kubevirt-executor.sh /bin/kubevirt-executor.sh
RUN chmod 755 /bin/kubevirt-executor.sh
