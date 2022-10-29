nixpkgsLib: with nixpkgsLib; {
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

        As the pihole container is running rootless this cannot be a privileged port (<1024).
      '';
    };

    hostPublicPort = mkOption {
      type = types.port;
      description = ''
        The public port on the host on which the ${service} port of the pihole container should be forwared to.

        This option can be used to together with the according `forwardPublicToInternal` to expose a pihole subservice on a privileged port,
        e.g., if you want to expose the DNS service on port 53.
      '';
      default = publicDefaultPort;
    };

    forwardPublicToInternal = mkOption {
      type = types.bool;
      description = ''
        Enable port-forwarding between the public & the internal port of the host.
        This effectively makes pihole's ${service} port available on the network to which the host is connected to.

        Use this option together with the according `hostPublicPort` to expose a pihole subservice on a privileged port.
      '';
      default = false;
    };
  };
}
