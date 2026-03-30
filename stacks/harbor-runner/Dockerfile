# DinD base image published from blouin-labs/dind-runner.
# Contains: Docker CE, dockremap user, daemon.json, base entrypoint.
FROM ghcr.io/blouin-labs/dind-runner:latest

# Override entrypoint to add SSH key setup for gh-deploy@harbor-srv.
COPY dind-entrypoint.sh /dind-entrypoint.sh
