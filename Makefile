LD_FLAGS:=-s -w -extldflags -static
GO_BUILD_FLAGS:=-trimpath -ldflags "$(LD_FLAGS)"
GOPATH:=$(shell go env GOPATH)
# multi-platform doesn't work for sbom and scanning tools
#PLATFORMS:=linux/386,linux/amd64,linux/arm/v6,linux/arm/v7,linux/arm64,linux/ppc64le,linux/s390x
PLATFORMS:=linux/amd64
base_name:=alpine:latest
base_digest:=$(shell regctl image digest "$(base_name)")
git_short:=$(shell git rev-parse --short HEAD)
date_git:=$(shell date -d "@$(shell git log -1 --format=%at)" +%Y-%m-%dT%H:%M:%SZ --utc)

.PHONY: all fmt vet test lint lint-go lint-md vendor docker regctl-setup zot mutate sbom scan attach push .FORCE

.FORCE:

all: fmt vet test lint hello docker oci-layout regctl-setup zot mutate sbom-syft scan-grype attach sign push

clean:
	-docker stop zot
	rm -r oci-layout oci-layout.tar sbom.json scan.json

fmt:
	go fmt ./...

vet:
	go vet ./...

test:
	go test -cover ./...

lint: lint-go lint-md

lint-go: $(GOPATH)/bin/staticcheck .FORCE
	$(GOPATH)/bin/staticcheck -checks all ./...

$(GOPATH)/bin/staticcheck: 
	go install "honnef.co/go/tools/cmd/staticcheck@latest"

lint-md: .FORCE
	docker run --rm -v "$(PWD):/workdir:ro" ghcr.io/igorshubovych/markdownlint-cli:latest \
	  --ignore vendor .

vendor:
	go mod vendor

hello: .FORCE
	CGO_ENABLED=0 go build ${GO_BUILD_FLAGS} -o $@ .

docker: .FORCE
	docker buildx build --platform="$(PLATFORMS)" \
		--build-arg date_git="$(date_git)" \
	  --output type=oci,dest=oci-layout.tar,name=demo:latest .

oci-layout: oci-layout.tar .FORCE
	regctl image import ocidir://oci-layout oci-layout.tar

regctl-setup: .FORCE
	regctl registry set --tls=disabled localhost:5207

zot: .FORCE
	docker run --rm -d --name zot \
		-p 127.0.0.1:5207:5000 \
		-u "$(shell id -u):$(shell id -g)" \
	  -v "$(shell pwd)/oci-layout:/var/lib/registry/demo" \
		zot:latest
#	  ghcr.io/project-zot/zot-linux-amd64:v1.4.0

mutate: .FORCE
	regctl image mod ocidir://oci-layout:latest --replace \
		--time-max "$(date_git)" \
		--annotation "org.opencontainers.image.created=$(date_git)" \
  	--annotation "org.opencontainers.image.base.name=$(base_name)" \
  	--annotation "org.opencontainers.image.base.digest=$(base_digest)"

# SBOM tools
sbom-syft: .FORCE
	syft packages oci-dir:oci-layout -o cyclonedx-json --file sbom.json

sbom-syft-spdx: .FORCE
	syft packages oci-dir:oci-layout -o spdx-json --file sbom.json

sbom-trivy: .FORCE
	trivy sbom --sbom-format cyclonedx --artifact-type fs --output sbom.json .

# Vulnerability Scanners
scan-grype: .FORCE
	grype oci-dir:oci-layout --output json --file scan.json

scan-snyk: .FORCE
	snyk oci-archive:oci-layout.tar --json-file-output=scan.json

scan-trivy: .FORCE
	# trivy image --input oci-layout --format json --output scan.json
	trivy sbom --sbom-format cyclonedx --artifact-type archive --output sbom.json oci-layout

# Signing tools
cosign.*:
	cosign generate-key-pair

attach: .FORCE
	regctl artifact put \
	  --config-media-type application/vnd.oci.image.config.v1+json \
		-f sbom.json --media-type "application/vnd.cyclonedx+json" \
		--annotation org.opencontainers.artifact.type=sbom \
		--annotation org.example.sbom.type=cyclonedx-json \
    --format '{{ printf "%s\n" .Manifest.GetDescriptor.Digest }}' \
		--refers ocidir://oci-layout:latest
	regctl artifact put \
	  --config-media-type application/vnd.oci.image.config.v1+json \
		-f scan.json --media-type "application/json" \
		--annotation org.opencontainers.artifact.type=scan \
		--annotation org.example.scan.type=grype-json \
    --format '{{ printf "%s\n" .Manifest.GetDescriptor.Digest }}' \
		--refers ocidir://oci-layout:latest

sign: cosign.key .FORCE
	cosign sign --key cosign.key "localhost:5207/demo@$(shell regctl image digest ocidir://oci-layout)"

push: .FORCE
	regctl image copy -v info --referrers --digest-tags \
	  ocidir://oci-layout localhost:5000/demo:latest

run: .FORCE
	docker pull localhost:5000/demo:latest
	docker run --rm localhost:5000/demo:latest hello world

inspect-list: .FORCE
	regctl artifact list --force-get localhost:5000/demo:latest

inspect-json: .FORCE
	for dig in $$(regctl artifact list localhost:5000/demo:latest --format '{{range $$i, $$d := .Descriptors}}{{println $$d.Digest}}{{end}}'); do \
		echo "Digest: $$dig"; \
		regctl artifact get localhost:5000/demo@$$dig | head -20; \
		echo "..."; echo; \
	done
