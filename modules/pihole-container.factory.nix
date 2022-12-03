{ piholeFlake, lingerFlake }: { config, pkgs, lib, ... }: with lib; with builtins; let
  inherit (import ../lib/util.nix) extractContainerEnvVars extractContainerFTLEnvVars;

  mkContainerEnvOption = { envVar, ... }@optionAttrs:
    (mkOption (removeAttrs optionAttrs [ "envVar" ]))
    // { inherit envVar; };

  cfg = config.services.pihole;
  hostUserCfg = config.users.users.${cfg.hostConfig.user};
  tmpDirIsResetAtBoot = config.boot.cleanTmpDir || config.boot.tmpOnTmpfs;
  systemTimeZone = config.time.timeZone;
  defaultPiholeVolumesDir = "${config.users.users.${cfg.hostConfig.user}.home}/pihole-volumes";

in rec {
  options = {
    services.pihole = {
      enable = mkEnableOption "PiHole as a rootless podman container";

      hostConfig = {
        user = mkOption {
          type = types.str;
          description = ''
            The username of the user on the host which should run the pihole container.
            Needs to be able to run rootless podman.
          '';
        };

        enableLingeringForUser = mkOption {
          type = with types; oneOf [ bool (enum [ "suppressWarning" ]) ];
          description = ''
            If true lingering (see `loginctl enable-linger`) is enabled for the host user running pihole.
            This is necessary as otherwise starting the pihole container will fail if there is no active session for the host user.
            If false a warning is printed during the build to remind you of the issue.

            Set to "suppressWarning" if the issue is solved otherwise or does not apply.
          '';
          default = false;
        };

        containerName = mkOption {
          type = types.str;
          description = ''
            The name of the podman container in which pihole will be started.
          '';
          default = "pihole_${cfg.hostConfig.user}";
        };

        persistVolumes = mkOption {
          type = types.bool;
          description = "Whether to use podman volumes to persist pihole's ad-hoc configuration across restarts.";
          default = false;
        };

        volumesPath = mkOption {
          type = types.str;
          description = ''
            The path where the persistent data of the pihole container should be stored.
            The different used volumes are created automatically.
            Needs to be writable by the user running the pihole container.
          '';
          default = defaultPiholeVolumesDir;
          example = "/home/pihole-user/pihole-volumes";
        };

        dnsPort = mkOption {
          type = with types; nullOr (either port str);
          description = ''
            THe port on which PiHole's DNS service shoud be exposed.
            Either pass a port number as integer or a string in the format `ip:port` (see [Docker docs](https://docs.docker.com/engine/reference/run/#expose-incoming-ports) for details).

            If this option is not specified the DNS service will not be exposed on the host.
            Remember that if the container is running rootless exposing on a privileged port is not possible.
          '';
          default = null;
        };

        dhcpPort = mkOption {
          type = with types; nullOr (either port str);
          description = ''
            THe port on which PiHole's DHCP service shoud be exposed.
            Either pass a port number as integer or a string in the format `ip:port` (see [Docker docs](https://docs.docker.com/engine/reference/run/#expose-incoming-ports) for details).

            If this option is not specified the DHCP service will not be exposed on the host.
            Remember that if the container is running rootless exposing on a privileged port is not possible.
          '';
          default = null;
        };

        webPort = mkOption {
          type = with types; nullOr (either port str);
          description = ''
            THe port on which PiHole's web interface shoud be exposed.
            Either pass a port number as integer or a string in the format `ip:port` (see [Docker docs](https://docs.docker.com/engine/reference/run/#expose-incoming-ports) for details).

            If this option is not specified the web interface will not be exposed on the host.
            Remember that if the container is running rootless exposing on a privileged port is not possible.
          '';
          default = null;
        };

        suppressTmpDirWarning = mkOption {
          type = types.bool;
          description = ''
            Set to `true` if you have taken precautions s.t. rootless podman does not leave traces in `/tmp`.

            Failing to do so can cause rootless podman to fail to start at reboot (see https://github.com/containers/podman/issues/4057).
            If `boot.cleanTmpDir` or `boot.tmpOnTmpfs` is set then you do not have to set this option.
          '';
          default = false;
        };
      };


      piholeConfig = {
        tz = mkContainerEnvOption {
          type = types.str;
          description = "Set your timezone to make sure logs rotate at local midnight instead of at UTC midnight.";
          default = systemTimeZone;
          envVar = "TZ";
        };

        interface = mkContainerEnvOption {
          type = types.str;
          description = ''
            Set the interface of the pihole container on which it should respond to DNS requests.

            Note: Configuring "Allow only local requests" is currently not supported by the pihole image at startup but can be done later through the web interface.
          '';
          default = "tap0";
          envVar = "INTERFACE";
        };

        web = {
          password = mkContainerEnvOption {
            type = with types; nullOr str;
            description = ''
              The password for the pihole admin interface.
              If not given a random password will be generated an can be retrieved from the service logs.
            '';
            default = null;
            envVar = "WEBPASSWORD";
          };

          # TODO password-file

          virtualHost = mkContainerEnvOption {
            type = types.str;
            description = "What your web server 'virtual host' is, accessing admin through this Hostname/IP allows you to make changes to the whitelist/blacklists in addition to the default 'http://pi.hole/admin/' address";
            envVar = "VIRTUAL_HOST";
          };

          layout = mkContainerEnvOption {
            type = types.enum [ "boxed" "traditional" ];
            description = "Use boxed layout (helpful when working on large screens)";
            default = "boxed";
            envVar = "WEBUIBOXEDLAYOUT";
          };

          theme = mkContainerEnvOption {
            type = types.enum [ "default-dark" "default-darker" "default-light" "default-auto" "lcars" ];
            description = "User interface theme to use.";
            default = "default-light";
            envVar = "WEBTHEME";
          };
        };

        dns = {
          upstreamServers = mkContainerEnvOption {
            type = with types; nullOr (listOf str);
            description = ''
              Upstream DNS server(s) for Pi-hole to forward queries to.
              (supports non-standard ports with #[port number]) e.g [ "127.0.0.1#5053" "8.8.8.8" "8.8.4.4" ]
              (supports Docker service names and links instead of IPs) e.g [ "upstream0" "upstream1" ] where upstream0 and upstream1 are the service names of or links to docker services.

              Note: The existence of this environment variable assumes this as the sole management of upstream DNS.
              Upstream DNS added via the web interface will be overwritten on container restart/recreation.
            '';
            default = null;
            envVar = "PIHOLE_DNS_";
          };

          dnssec = mkContainerEnvOption {
            type = types.bool;
            description = "Enable DNSSEC support";
            default = false;
            envVar = "DNSSEC";
          };

          bogusPriv = mkContainerEnvOption {
            type = types.bool;
            description = "Never forward reverse lookups for private ranges.";
            default = true;
            envVar = "DNS_BOGUS_PRIV";
          };

          fqdnRequired = mkContainerEnvOption {
            type = types.bool;
            description = "Never forward non-FQDNs.";
            default = true;
            envVar = "DNS_FQDN_REQUIRED";
          };
        };

        revServer = {
          enable = mkContainerEnvOption {
            type = types.bool;
            description = "Enable DNS conditional forwarding for device name resolution.";
            default = false;
            envVar = "REV_SERVER";
          };

          domain = mkContainerEnvOption {
            type = with types; nullOr str;
            description = "If conditional forwarding is enabled, set the domain of the local network router.";
            default = null;
            envVar = "REV_SERVER_DOMAIN";
          };

          target = mkContainerEnvOption {
            type = with types; nullOr str;
            description = "If conditional forwarding is enabled, set the IP of the local network router.";
            default = null;
            envVar = "REV_SERVER_TARGET";
          };

          cidr = mkContainerEnvOption {
            type = with types; nullOr str;
            description = "If conditional forwarding is enabled, set the reverse DNS zone (e.g. 192.168.0.0/24)";
            default = null;
            envVar = "REV_SERVER_CIDR";
          };
        };

        ftl = mkOption {
          type = with types; attrsOf str;
          description = ''
            Set any additional FTL option under this key.

            You can find the different options in the pihole docs: https://docs.pi-hole.net/ftldns/configfile
            The names should be exactly like in the pihole docs.
          '';
          example = { LOCAL_IPV4 = "192.168.0.100"; };
          default = {};
        };

        dhcp = {
          enable = mkContainerEnvOption {
            type = types.bool;
            description = ''
              Enable DHCP server.
              Static DHCP leases can be configured with a custom /etc/dnsmasq.d/04-pihole-static-dhcp.conf
            '';
            default = false;
            envVar = "DHCP_ACTIVE";
          };

          start = mkContainerEnvOption {
            type = with types; nullOr str;
            description = "Start of the range of IP addresses to hand out by the DHCP server (mandatory if DHCP server is enabled).";
            default = null;
            example = "192.168.0.10";
            envVar = "DHCP_START";
          };

          end = mkContainerEnvOption {
            type = with types; nullOr str;
            description = "End of the range of IP addresses to hand out by the DHCP server (mandatory if DHCP server is enabled).";
            default = null;
            example = "192.168.0.20";
            envVar = "DHCP_END";
          };

          router = mkContainerEnvOption {
            type = with types; nullOr str;
            description = "Router (gateway) IP address sent by the DHCP server (mandatory if DHCP server is enabled).";
            default = null;
            example = "192.168.0.1";
            envVar = "DHCP_ROUTER";
          };

          leasetime = mkContainerEnvOption {
            type = types.int;
            description = "DHCP lease time in hours.";
            default = 24;
            envVar = "DHCP_LEASETIME";
          };

          domain = mkContainerEnvOption {
            type = types.str;
            description = "Domain name sent by the DHCP server.";
            default = "lan";
            envVar = "PIHOLE_DOMAIN";
          };

          ipv6 = mkContainerEnvOption {
            type = types.bool;
            description = "Enable DHCP server IPv6 support (SLAAC + RA).";
            default = false;
            envVar = "DHCP_IPv6";
          };

          rapid-commit = mkContainerEnvOption {
            type = types.bool;
            description = "Enable DHCPv4 rapid commit (fast address assignment).";
            default = false;
            envVar = "DHCP_rapid_commit";
          };
        };

        queryLogging = mkContainerEnvOption {
          type = types.bool;
          description = "Enable query logging or not.";
          default = true;
            envVar = "QUERY_LOGGING";
        };

        temperatureUnit = mkContainerEnvOption {
          type = types.enum [ "c" "k" "f" ];
          description = "Set preferred temperature unit to c: Celsius, k: Kelvin, or f Fahrenheit units.";
          default = "c";
          envVar = "TEMPERATUREUNIT";
        };
      };
    };
  };

  config = mkIf cfg.enable {

    assertions = [
      { assertion = length hostUserCfg.subUidRanges > 0 && length hostUserCfg.subGidRanges > 0;
        message = ''
          The host user most have configured subUidRanges & subGidRanges as pihole is running in a rootless podman container.
        '';
      }
    ];

    warnings = (optional (cfg.hostConfig.enableLingeringForUser == false) ''
      If lingering is not enabled for the host user which is running the pihole container then he service might be stopped when no user session is active.

      Set `services.pihole.hostConfig.enableLingeringForUser` to `true` to manage systemd's linger setting through the `linger-flake` dependency.
      Set it to "suppressWarning" if you manage lingering in a different way.
    '') ++ (optional (!tmpDirIsResetAtBoot && !cfg.hostConfig.suppressTmpDirWarning) ''
      Rootless podman can leave traces in `/tmp` after shutdown which can break the startup of new containers at the next boot.
      See https://github.com/containers/podman/issues/4057 for details.

      To avoid problems consider to clean `/tmp` of any left-overs from podman before the next startup.
      The NixOS config options `boot.cleanTmpDir` or `boot.tmpOnTmpfs` can be helpful.
      Enabling either of these disables this warning.
      Otherwise you can also set `services.pihole.hostConfig.suppressTmpDirWarning` to `true` to disable the warning.
    '');

    services.linger = mkIf (cfg.hostConfig.enableLingeringForUser == true) {
      enable = true;
      users = [ cfg.hostConfig.user ];
    };

    systemd.services."pihole-rootless-container" = {
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      requires = [ "network-online.target" ];

      # required to make `newuidmap` available to the systemd service (see https://github.com/NixOS/nixpkgs/issues/138423)
      path = [ "/run/wrappers" ];

      serviceConfig = let
        containerEnvVars = extractContainerEnvVars options.services.pihole cfg;
        containerFTLEnvVars = extractContainerFTLEnvVars cfg;
      in {
        ExecStartPre = mkIf cfg.hostConfig.persistVolumes [
          "${pkgs.coreutils}/bin/mkdir -p ${cfg.hostConfig.volumesPath}/etc-pihole"
          "${pkgs.coreutils}/bin/mkdir -p ${cfg.hostConfig.volumesPath}/etc-dnsmasq.d"
          ''${pkgs.podman}/bin/podman rm --ignore "${cfg.hostConfig.containerName}"''
        ];

        ExecStart = ''
          ${pkgs.podman}/bin/podman run \
            --rm \
            --rmi \
            --name="${cfg.hostConfig.containerName}" \
            ${
              if cfg.hostConfig.persistVolumes then ''
              -v ${cfg.hostConfig.volumesPath}/etc-pihole:/etc/pihole \
              -v ${cfg.hostConfig.volumesPath}/etc-dnsmasq.d:/etc/dnsmasq.d \
              '' else ""
            } \
            ${
              if !(isNull cfg.hostConfig.dnsPort) then ''
              -p ${toString cfg.hostConfig.dnsPort}:53/tcp \
              -p ${toString cfg.hostConfig.dnsPort}:53/udp \
              '' else ""
            } \
            ${
              if !(isNull cfg.hostConfig.dhcpPort) then ''
              -p ${toString cfg.hostConfig.dhcpPort}:67/udp \
              '' else ""
            } \
            ${
              if !(isNull cfg.hostConfig.webPort) then ''
              -p ${toString cfg.hostConfig.webPort}:80/tcp \
              '' else ""
            } \
            ${
              concatStringsSep " \\\n"
                (map (envVar: "  -e '${envVar.name}=${toString envVar.value}'") (containerEnvVars ++ containerFTLEnvVars))
            } \
            docker-archive:${piholeFlake.packages.${pkgs.system}.piholeImage}
        '';

        User = "${cfg.hostConfig.user}";
      };

      postStop = ''
        while ${pkgs.podman}/bin/podman container exists "${cfg.hostConfig.containerName}"; do
          ${pkgs.coreutils-full}/bin/sleep 2;
        done
      '';
    };
  };
}
