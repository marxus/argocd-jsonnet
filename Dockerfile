FROM alpine:3.22 AS build
COPY gitshim helmshim /jsonnet/
ARG TARGETARCH
RUN cd /tmp \
&& apk add --no-cache curl \
&&  curl -L "https://get.helm.sh/helm-v3.15.1-linux-$TARGETARCH.tar.gz" | tar -xz --strip-components 1 \
&&  curl -L "https://github.com/jsonnet-bundler/jsonnet-bundler/releases/download/v0.6.0/jb-linux-$TARGETARCH" -o jb \
&&  curl -L "https://github.com/marxus/go-jsonnet-ext/releases/download/v0.20.0/go-jsonnet-linux-$TARGETARCH.tar.gz" | tar -xz \
&&  curl -L "https://github.com/mikefarah/yq/releases/download/v4.44.1/yq_linux_$TARGETARCH.tar.gz" | tar -xz && mv "yq_linux_$TARGETARCH" yq \
&&  cp helm jb jsonnet yq /jsonnet \
&&  chmod +x /jsonnet/*

FROM alpine:3.22
COPY --from=build /jsonnet /jsonnet
