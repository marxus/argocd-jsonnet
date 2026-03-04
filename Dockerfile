FROM alpine:3.22 AS build
COPY gitshim helmshim /tanka/
ARG TARGETARCH
RUN cd /tmp \
&& apk add --no-cache curl \
&&  curl -L "https://get.helm.sh/helm-v4.1.1-linux-$TARGETARCH.tar.gz" | tar -xz --strip-components 1 \
&&  curl -L "https://github.com/jsonnet-bundler/jsonnet-bundler/releases/download/v0.6.0/jb-linux-$TARGETARCH" -o jb \
&&  curl -L "https://github.com/grafana/tanka/releases/download/v0.36.3/tk-linux-$TARGETARCH" -o tk \
&&  curl -L "https://github.com/mikefarah/yq/releases/download/v4.44.1/yq_linux_$TARGETARCH.tar.gz" | tar -xz && mv "yq_linux_$TARGETARCH" yq \
&&  mkdir helm-git && curl -L "https://github.com/aslafy-z/helm-git/archive/refs/tags/v1.5.2.tar.gz" | tar -xz --strip-components 1 -C helm-git \
&&  cp helm jb tk yq /tanka \
&&  cp -r helm-git /tanka \
&&  chmod +x /tanka/*

FROM alpine:3.22
COPY --from=build /tanka /tanka
