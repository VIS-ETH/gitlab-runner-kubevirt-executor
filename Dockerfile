FROM alpine AS assembler
WORKDIR /assembler

RUN apk add curl \
  && curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
  && mv kubectl /bin/kubectl

RUN curl -L --output /bin/gitlab-runner "https://s3.dualstack.us-east-1.amazonaws.com/gitlab-runner-downloads/latest/binaries/gitlab-runner-linux-amd64"

COPY kubevirt-executor.sh /bin/kubevirt-executor.sh
