#!/bin/bash

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# cgroup v2 nesting for Docker-in-Docker.
#
# When this container starts, its processes (including PID 1) live in the root
# of its cgroup namespace. As soon as runc enables a threaded controller
# (cpu/cpuset/pids) in cgroup.subtree_control while that root is populated,
# the root becomes "domain threaded". Every child cgroup created afterwards is
# "domain invalid", so runc either refuses containers that request domain
# controllers (memory/io/cpu/hugetlb) or silently switches the container parent
# cgroup to threaded mode, permanently disabling memory limits and accounting
# (docker stats shows 0B).
#
# Fix: move all processes out of the namespace root into /init before dockerd
# starts, then enable every available controller in the now-empty root. The
# root stays a plain domain and nested containers get real domain cgroups.
#
# See Documentation/admin-guide/cgroup-v2.rst ("No Internal Process
# Constraint" and "Threads") for the kernel rules this works around.

set -eu

if [ ! -f /sys/fs/cgroup/cgroup.controllers ]; then
    echo "cgroup v2 not in use; skipping"
    exit 0
fi

# Safety: only touch the cgroup tree when the cgroup namespace is delegated to
# us (Docker mounts cgroup2 with nsdelegate for --cgroupns=private). Without
# this, /sys/fs/cgroup could be the host hierarchy.
if ! grep -q 'nsdelegate' /proc/self/mountinfo; then
    echo "cgroup namespace is not delegated (missing nsdelegate); skipping"
    exit 0
fi

if [ "$(cat /proc/self/cgroup)" != "0::/" ]; then
    echo "not at the root of a private cgroup namespace; skipping"
    exit 0
fi

# A threaded root is irreversible; if we somehow get here with one, don't
# make things worse.
root_type="$(cat /sys/fs/cgroup/cgroup.type 2>/dev/null || true)"
case "${root_type}" in
    threaded|"domain threaded")
        echo "cgroup namespace root is already '${root_type}'; skipping"
        exit 0
        ;;
esac

mkdir -p /sys/fs/cgroup/init

# Moving every process out of the root must happen before enabling domain
# controllers, otherwise the writes fail with EBUSY. Do not gate this on the
# file appearing non-empty: cgroupfs files report st_size 0.
xargs -rn1 < /sys/fs/cgroup/cgroup.procs > /sys/fs/cgroup/init/cgroup.procs || true

# Enable all controllers in the root; this is allowed because it is empty.
sed -e 's/ / +/g' -e 's/^/+/' < /sys/fs/cgroup/cgroup.controllers > /sys/fs/cgroup/cgroup.subtree_control

echo "cgroup v2 nesting enabled: subtree_control=$(cat /sys/fs/cgroup/cgroup.subtree_control)"
