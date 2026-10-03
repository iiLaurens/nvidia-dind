# NVIDIA DinD (Docker in Docker) Container

Isolated DinD (Docker in Docker) container for developing and deploying Docker containers using NVIDIA GPUs and the NVIDIA container toolkit. Useful for deploying the Docker engine with NVIDIA in Kubernetes.

Host is required to have the NVIDIA container toolkit installed and set up. Privileged mode or [Sysbox](https://github.com/nestybox/sysbox) configured with NVIDIA GPUs are required like any other DinD container with root requirement.

```bash
docker run --gpus 1 -it --privileged ghcr.io/ehfd/nvidia-dind:latest
```

Use `-e DOCKERD_FLAG=` to append command-line flags to `dockerd`.

## Fork notes

This fork adds `cgroupv2-nesting.sh`, executed by `supervisord.conf` right
before `dockerd` starts. It moves the container's processes into the `/init`
cgroup and enables every available controller on the (now empty) cgroup
namespace root.

Without it, on cgroup v2 hosts the namespace root turns into `domain threaded`
as soon as the first nested container without memory/CPU limits is created.
After that, nested containers that request domain controllers fail with
`cannot enter cgroupv2 "/sys/fs/cgroup/docker" with domain controllers -- it is
in threaded mode`, and `docker stats` reports `0B` because the memory
controller never reaches the container cgroups.

Build and publish to your own registry by pushing to your fork; the workflow
publishes to `ghcr.io/${{ github.repository }}`.
