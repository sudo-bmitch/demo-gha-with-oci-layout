# syntax=docker/dockerfile:1

FROM --platform=$BUILDPLATFORM golang:1.17 as build

WORKDIR /src
COPY . /src/

ARG TARGETOS
ARG TARGETARCH
# date_git forces a cache miss after a git commit
ARG date_git
RUN --mount=type=cache,id=gomod,target=/go/pkg/mod/cache \
    --mount=type=cache,id=goroot,target=/root/.cache/go-build \
    GOOS=${TARGETOS} GOARCH=${TARGETARCH} CGO_ENABLED=0 \
    go build -trimpath -ldflags "-s -w -extldflags -static" -o hello .

FROM alpine:latest
COPY --from=build /src/hello /bin/hello
