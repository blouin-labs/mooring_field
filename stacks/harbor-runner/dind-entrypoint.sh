#!/bin/bash
set -e

# Enforce runner scope — only accept registration to the blouin-labs org.
# This prevents the runner from being registered to another user's or org's account
# even if the token is somehow obtained.
if [[ "${ACTIONS_RUNNER_INPUT_URL}" != "https://github.com/blouin-labs"* ]]; then
  echo "ERROR: ACTIONS_RUNNER_INPUT_URL must be the blouin-labs org: https://github.com/blouin-labs"
  echo "       Got: '${ACTIONS_RUNNER_INPUT_URL}'"
  exit 1
fi

# Clean up stale Docker runtime files from a previous run
# (--restart reuses the same container filesystem, so these persist)
rm -f /var/run/docker.pid /var/run/docker.sock
rm -rf /var/run/docker/

# Start Docker daemon — security defaults come from /etc/docker/daemon.json
dockerd &>/var/log/dockerd.log &
DOCKERD_PID=$!
echo "Waiting for Docker daemon..."
timeout 30 sh -c 'until docker info >/dev/null 2>&1; do sleep 0.5; done'
echo "Docker daemon ready."

# Mask container-detection signals so the runner allows container: jobs.
# The runner binary checks two things to detect if it's in a container:
#   1. /.dockerenv exists
#   2. /proc/1/cgroup contains ':/docker/'
# Both must be suppressed; removing only /.dockerenv is not enough.
# The bind mount works because the container runs with privileged: true.
rm -f /.dockerenv
printf '' > /tmp/empty-cgroup
mount --bind /tmp/empty-cgroup /proc/1/cgroup

# Ensure the work volume is owned by the runner user.
# The named volume may be initialized as root on first use.
chown -R runner:runner /home/runner/_work

# Set up SSH key for gh-deploy@harbor-srv.
# GH_DEPLOY_SSH_KEY_B64 is the base64-encoded private key (no newlines).
if [ -z "${GH_DEPLOY_SSH_KEY_B64:-}" ]; then
  echo "ERROR: GH_DEPLOY_SSH_KEY_B64 is not set" >&2
  exit 1
fi
install -d -m 700 -o runner -g runner /home/runner/.ssh
printf '%s' "${GH_DEPLOY_SSH_KEY_B64}" | base64 -d > /home/runner/.ssh/gh_deploy_key
chmod 600 /home/runner/.ssh/gh_deploy_key
chown runner:runner /home/runner/.ssh/gh_deploy_key

# Write SSH client config so workflow steps can use "harbor-srv" as a hostname alias
# without callers needing to pass -i or specify the user explicitly.
cat > /home/runner/.ssh/config << 'EOF'
Host harbor-srv
  HostName 192.168.1.5
  User gh-deploy
  IdentityFile ~/.ssh/gh_deploy_key
  IdentitiesOnly yes
  StrictHostKeyChecking yes
EOF
chmod 600 /home/runner/.ssh/config
chown runner:runner /home/runner/.ssh/config

# Pre-populate known_hosts so SSH connections are non-interactive.
# Done at container start under root so it happens once and before runner takes over.
ssh-keyscan -H 192.168.1.5 >> /home/runner/.ssh/known_hosts 2>/dev/null
chmod 644 /home/runner/.ssh/known_hosts
chown runner:runner /home/runner/.ssh/known_hosts

# Capture config vars (interpolated as root before su, so they're available in subshells)
_URL="${ACTIONS_RUNNER_INPUT_URL}"
_TOKEN="${ACTIONS_RUNNER_INPUT_TOKEN}"
_NAME="${ACTIONS_RUNNER_INPUT_NAME:-harbor-srv-docker}"
_LABELS="${ACTIONS_RUNNER_INPUT_LABELS:-harbor-srv-docker}"

# Configure runner as runner user
su - runner -s /bin/bash -c "
  cd /home/runner
  ./config.sh \
    --url '${_URL}' \
    --token '${_TOKEN}' \
    --name '${_NAME}' \
    --labels '${_LABELS}' \
    --unattended --replace
"

# Deregister + stop dockerd on any exit
cleanup() {
  echo "Deregistering runner..."
  su - runner -s /bin/bash -c "
    cd /home/runner && ./config.sh remove --token '${_TOKEN}'
  " || true
  kill "${DOCKERD_PID}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Run the runner as runner user
su - runner -s /bin/bash -c "cd /home/runner && ./run.sh"
