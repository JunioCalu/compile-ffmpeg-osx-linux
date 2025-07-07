#!/bin/bash
# cgroups fixer. See: https://gitlab.com/-/snippets/3722198#resolution
set -euo pipefail

error() {
    echo "$*"
    exit 1
}

dev_container_count="$(docker ps --filter label=devcontainer.metadata --quiet --no-trunc | wc -l)"

if [[ $dev_container_count -gt 1 ]]; then
    # Show table of dev containers
    docker ps --filter label=devcontainer.metadata --format 'table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.CreatedAt}}'

    # Prompt user to select from available dev containers
    echo
    read -rp 'Enter the name of the dev container to fix: ' dev_container_name
    echo
    dev_container_id="$(docker inspect --format '{{.Id}}' "$dev_container_name")" \
        || error "Invalid container name"
else
    dev_container_id="$(docker ps -q --no-trunc --filter label=devcontainer.metadata)"
fi

# Apply fix
dev_container_pid="$(docker inspect --format '{{.State.Pid}}' "$dev_container_id")"
cgroup_good="/user.slice/user-$UID.slice/user@$UID.service/user.slice/docker-$dev_container_id.scope/init"
cgroup_bad="/user.slice/user-$UID.slice/user@$UID.service/app.slice/docker.service"
# Filtering by cgroup probably isn't necessary, but it's probably a good idea.
# Only possible with pgrep 4+
cgflag="$(if [[ "$(pgrep --version | cut -d' ' -f4 | cut -d. -f1)" -ge 4 ]]; then echo "--cgroup=$cgroup_bad"; else :; fi)"
# shellcheck disable=SC2086
dockerd_pid="$(pgrep --parent "$dev_container_pid" $cgflag dockerd)" \
    || error "dockerd PID not found. This dev container's cgroup seems correct."
# shellcheck disable=SC2086
containerd_pid="$(pgrep --parent "$dockerd_pid" $cgflag containerd)" \
    || error "containerd PID not found. This dev container's cgroup seems correct."
for p in "$dockerd_pid" "$containerd_pid"; do
    echo "$p" | sudo tee /sys/fs/cgroup/"$cgroup_good"/cgroup.procs >/dev/null
done

echo ✨ cgroups fixed!
