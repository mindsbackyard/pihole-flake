# Pi-hole Flake

A NixOS flake providing a [Pi-hole](https://pi-hole.net) container & NixOS module for running it in a (rootless) podman container.

The flake provides a container image for Pi-hole by fetching the `pihole/pihole` image version defined in `pihole-image-base-info.nix`.
Currently the container image can be built for `x64_64-linux` and `aarch64-linux` systems.

Further the flake comes with a NixOS module that can be used to configure & run Pi-hole as a `systemd` service.
Contrary to NixOS' oci-container support this flake allows to run Pi-hole in a rootless container environment---which is also the main reason why this flake exists.
Another benefit of using the provided NixOS module is that it explicitly exposes the supported configuration options of the Pi-hole container.

## Configuring Pi-hole

All configuration options can be found under the key `service.pihole`.
The Pi-hole service can be enabled by setting `services.pihole.enable = true`.
Full descriptions of the configuration options can be found the in the module.
Example configurations can be found in the `examples` folder.

The module options are separate into two parts:
* **Host-specific options** which define how the Pi-hole container should be run on the host
* **Pi-hole-specific options** which configure the Pi-hole service in the container

### Host-specific options

All host-specific options are contained in `services.pihole.hostConfig`.
Among others the `hostConfig` contains the options for exposing the ports of Pi-hole's DNS, DHCP, and web UI components.
Remember if that if you run the service in a rootless container binding to priviledged ports is by default not possible.

To handle this limitation you can either:
* *Access the components on non-privileged ports:* This should be easily possible for the web & DNS components---if your DHCP server supports DNS servers with non-standard ports or if you configure your DNS resolvers to use a non-default port by other means.
  If you use Pi-hole's DHCP server then lookup your DHCP client's documentation on how to send DHCP requests to non-standard ports.
* *Use port-fowarding from a privileged to an unprivileged port*
* *Change the range of privileged ports:* see `sysctl net.ipv4.ip_unprivileged_port_start`

Also do not forget to open the exposed ports in NixOS' firewall otherwise you won't be able to access the services.

As the Pi-hole container supports to be run rootless, you need to configure which user should run the Pi-hole container via `services.pihole.hostConfig.user`.
This user needs a [subuid](https://nixos.org/manual/nixos/stable/options.html#opt-users.users._name_.subUidRanges)/[subgid](https://nixos.org/manual/nixos/stable/options.html#opt-users.users._name_.subGidRanges) ranges defined or [automatically configured](https://nixos.org/manual/nixos/stable/options.html#opt-users.users._name_.autoSubUidGidRange) s.t. she can run rootless podman containers.

If you want to persist your Pi-hole configuration (the changes you made via the UI) between container restarts take a look at `services.pihole.hostConfig.persistVolumes` and `services.pihole.hostConfig.volumesPath`.

Running rootless podman containers can be unstable and the systemd service can fail if certain precautions are not taken:
* The user running the Pi-hole container should be allowed to linger after all her sessions are closed.
  See `services.pihole.hostConfig.enableLingeringForUser` for details.
* The temporary directory used by rootless podman should be cleaned of any remains on system start.
  See `services.pihole.hostConfig.suppressTmpDirWarning` for details.

### Pi-hole options

All options for configuring Pi-hole itself can be found under the key `services.pihole.piholeConfig`.
The exposed options are mainly those listed as the environment variables of the [Docker image](https://github.com/pi-hole/docker-pi-hole#environment-variables) or of [FTLDNS](https://docs.pi-hole.net/ftldns/configfile/).
Though the options have been grouped to provide more structure (see the option declarations in the module for details).

## Updating[^1] the Pi-hole Image

Because this is a NixOS flake, when building the flake the Pi-hole container image that is used must be fixed.
Otherwise the hash of image cannot be known and the flake build would fail.
Therefore the used version of the image must be pinned before building the flake.

The image information is stored in `./pihole-image-info.ARCH.nix` where `ARCH` is either `amd64` or `arm64`.
To update both architectures to the newest Pi-hole image version execute:
```bash
nix develop
update-pihole-image-info --arch amd64
update-pihole-image-info --arch arm64
```

The `update-pihole-image-info` command determines the newest image digest available, pre-fetches the images into the nix-store, and updates the respective `./pihole-image-info.ARCH.nix` files.

[^1]: The image in the upstream repository is not updated regularly. Please use & update your local clone of the flake, instead of using the vanilla upstream version.
