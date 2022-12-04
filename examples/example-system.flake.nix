## This is an example flake-based NixOS configuration to show the use of the pihole-flake.
## The configuration is not complete and it is assumed that a `./configuration.nix` and `./hardware.nix` exists.
## The example will start Pi-hole in an unprivileged container and expose the DNS & web services on unpriviledged ports.
{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";

    # Opinionated: This config defines all (transitive) inputs of all used flakes explicitly
    # s.t we are in complete control of which packages & flake versions are used.
    # Otherwise it can happed that we use several versions of the same flake
    # because different other flakes which depend on it pinned it to different versions.
    # Especially with `nixpkgs` this can become a security (outdated packages) & resource problem (storage space).

    flake-utils.url = "github:numtide/flake-utils";

    # Required for making sure that Pi-hole continues running if the executing user has no active session.
    linger = {
      url = "github:mindsbackyard/linger-flake";
      inputs.flake-utils.follows = "flake-utils";
    };

    pihole = {
      url = "github:mindsbackyard/pihole-flake";
      inputs.nixpkgs.follow = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.linger.follows = "linger";
    };
  };

  outputs = { self, nixpkgs, linger, pihole, ... }:
    let
      system = "x86_64-linux";
      # use x86_64 packages from nixpkgs
      pkgs = nixpkgs.legacyPackages.${system};

    in {
      nixosConfigurations."nixos-example-system" = nixpkgs.lib.nixosSystem {
        # nixosSystem needs to know the system architecture
        inherit system;
        modules = [
          # a small module for enabling nix flakes
          { ... }: {
            nix = {
              packge = pkgs.nixFlakes;
              extraOptions = "experimental-features = nix-command flake";

              # Opinionated: use system flake's (locked) `nixpkgs` as default `nixpkgs` for flake commands
              # see https://dataswamp.org/~solene/2022-07-20-nixos-flakes-command-sync-with-system.html
              registry.nixpkgs.flake = nixpkgs;
            };
          }

          # some existing system & hardware configuration modules; it is assumed that a user named `pihole` is defined here
          # and that the user has sub-uids/gids configured (e.g. via the `users.users.pihole.subUidRanges/subGidRanges` options)
          ./configuration.nix
          ./hardware.nix

          # make the module declared by the linger flake available to our config
          linger.nixosModules.${system}.default
          pihole.nixosModules.${system}.default

          # in another module we can now configure the lingering behaviour (could also be part of ./configuration.nix)
          { ... }: {
            # required for stable restarts of the Pi-hole container (try to remove it to see the warning from the pihole-flake)
            boot.cleanTmpDir = true;

            # the Pi-hole service configuration
            services.pihole = {
              enable = true;
              hostConfig = {
                # define the service user for running the rootless Pi-hole container
                user = "pihole";
                enableLingeringForUser = true;

                # we want to persist change to the Pi-hole configuration & logs across service restarts
                # check the option descriptions for more information
                persistVolumes = true;

                # expose DNS & the web interface on unpriviledged ports on all IP addresses of the host
                # check the option descriptions for more information
                dnsPort = 5335;
                webProt = 8080;
              };
              piholeConfig.ftl = {
                # assuming that the host has this (fixed) IP and should resolve "pi.hole" to this address
                # check the option description & the FTLDNS documentation for more information
                LOCAL_IPV4 = "192.168.0.2";
              };
              piholeCOnfig.web = {
                virtualHost = "pi.hole";
                password = "password";
              };
            };

            # we need to open the ports in the firewall to make the service accessible beyond `localhost`
            # assuming that Pi-hole is exposed on the host interface `eth0`
            networking.firewall.interfaces.eth0 = {
              allowedTCPPorts = [ 5335 8080 ];
              allowedUDPPorts = [ 5335 ];
            };
          }
        ];
      };
    };
}
