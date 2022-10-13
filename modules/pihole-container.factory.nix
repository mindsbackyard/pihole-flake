{ piholeFlake, util }: { config, pkgs, lib, ... }: with lib; with builtins; let
  inherit (util) collectAttrFragments accessValueOfFragment;

  cfg = config.services.pihole;
  systemTimeZone = config.time.timeZone;
  defaultPiholeVolumesDir = "${config.users.users.${cfg.hostConfig.user}.home}/pihole-volumes";

  mkContainerEnvOption = { envVar, ... }@optionAttrs:
    (mkOption (removeAttrs optionAttrs [ "envVar" ]))
    // { inherit envVar; };

  mkHostPortsOption = { service, publicDefaultPort }: {
    hostInternalPort = mkOption {
      type = types.port;
      description = ''
        The internal port on the host on which the ${service} port of the pihole container should be exposed.
        Only needs to be specified if he container port should be exposed
        or if the port-forwarding for this service is enabled.
      '';
    };

    hostPublicPort = mkOption {
      type = types.port;
      description =
        "The public port on the host on which the ${service} port of the pihole container should be forwared to.";
      default = publicDefaultPort;
    };

    forwardPublicToInternal = mkOption {
      type = types.bool;
      description = ''
        Enable port-forwarding between the public & the internal port of the host.
        This effectively makes pihole's ${service} port available on the network to which the host is connected to.
      '';
      default = false;
    };
  };

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

        dns = mkHostPortsOption {
          service = "DNS";
          publicDefaultPort = 53;
        };

        dhcp = mkHostPortsOption {
          service = "DHCP";
          publicDefaultPort = 67;
        };

        web = mkHostPortsOption {
          service = "Web";
          publicDefaultPort = 80;
        };
      };


      piholeConfiguration = {
        tz = mkContainerEnvOption {
          type = types.str;
          description = "Set your timezone to make sure logs rotate at local midnight instead of at UTC midnight.";
          default = systemTimeZone;
          envVar = "TZ";
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
    systemd.services."pihole-rootless-container" = {
      serviceConfig = {
        ExecStart = ''
          ${pkgs.podman}/bin/podman run \
          --rm \
          --rmi \
          docker-archive:${self.packages.piholeImage}
        '';
        User = admin;
      };
    };
  };
}
