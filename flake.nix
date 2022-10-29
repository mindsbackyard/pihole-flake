{
  description = "Pihole docker image & NixOS module for configuring a rootless pihole container (w/ port-forwarding)";

  inputs = {
    nixpkgs.url = "nixpkgs/nixpkgs-unstable";

    flake-utils.url = "github:numtide/flake-utils";

    linger = {
      url = "github:mindsbackyard/linger-flake";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs = { self, nixpkgs, flake-utils, linger }: with flake-utils.lib; eachSystem (with system; [ x86_64-linux aarch64-linux ]) (curSystem:
    let
      pkgs = nixpkgs.legacyPackages.${curSystem};

      imageName = "pihole/pihole";
      imageBaseInfo = import ./pihole-image-base-info.nix;
      imageInfo = {
        ${system.x86_64-linux}.pihole = imageBaseInfo // {
          arch = "amd64";
          sha256 = "sha256-ln5wM8DVxzEWqlEpzG+H7UVfsNfqYrfzv/2lKXaVXTI=";
        };

        ${system.aarch64-linux}.pihole = imageBaseInfo // {
          arch = "arm64";
          sha256 = "sha256-OIZf61nuPn+dJQdnLe807T2fJUJ5fKQqr5K4/Vt3IC4=";
        };
      };

      piholeImage = pkgs.dockerTools.pullImage imageInfo.${curSystem}.pihole;

    in {
      packages = {
        inherit piholeImage;
        default = piholeImage;
      };

      nixosModules.default = (import ./modules/pihole-container.factory.nix) {
        piholeFlake = self;
        lingerFlake = linger;
      };

      devShells.default = let
        updatePiholeImageInfoScript = pkgs.writeShellScriptBin "update-pihole-image-info" ''
          INSPECT_RESULT=`skopeo inspect "docker://${imageName}:latest"`
          IMAGE_DIGEST=`echo $INSPECT_RESULT | jq '.Digest'`
          LATEST_LABEL=`echo $INSPECT_RESULT | jq '.Labels."org.opencontainers.image.version"'`

          cat >pihole-image-base-info.nix <<EOF
          {
            imageName = "${imageName}";
            imageDigest = $IMAGE_DIGEST;
            finalImageTag = $LATEST_LABEL;
            os = "linux";
          }
          EOF
        '';

        in pkgs.mkShell {
          packages = with pkgs; [
            dig
            skopeo
            jq
            updatePiholeImageInfoScript
          ];

          inputsFrom = [ self.packages.${curSystem}.default ];
        };
    }
  );
}
