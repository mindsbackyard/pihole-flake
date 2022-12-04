{
  description = "A NixOS flake providing a Pi-hole container & NixOS module for running it in a (rootless) podman container.";

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

      imageInfo = {
        ${system.x86_64-linux}.pihole = import ./pihole-image-info.amd64.nix;
        ${system.aarch64-linux}.pihole = import ./pihole-image-info.arm64.nix;
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
        imageName = "pihole/pihole";
        updatePiholeImageInfoScript = pkgs.writeShellScriptBin "update-pihole-image-info" ''
          while [[ $# -gt 0 ]]; do
            case $1 in
              --arch)
                ARCH="$2"
                if [[ ($ARCH != 'amd64') && ($ARCH != 'arm64') ]]; then
                  echo '--arch must be either "amd64" or "arm64"'
                  exit 1
                fi
                shift # past argument
                shift # past value
                ;;
              *)
                echo "Unknown option $1"
                exit 1
                ;;
            esac
          done

          if [[ -z "$ARCH" ]]; then
            echo 'You must provide the "--arch [amd64|arm64]" option to specify which Pi-hole image should be updated.'
            exit 1
          fi

          INSPECT_RESULT=`skopeo inspect "docker://${imageName}:latest"`
          IMAGE_DIGEST=`echo $INSPECT_RESULT | jq '.Digest'`
          LATEST_LABEL=`echo $INSPECT_RESULT | jq '.Labels."org.opencontainers.image.version"'`

          IMAGE_INFO=`nix-prefetch-docker --os linux --arch "$ARCH" --image-name '${imageName}' --image-digest "$IMAGE_DIGEST" --final-image-tag "$LATEST_LABEL"`
          echo "$IMAGE_INFO" >"pihole-image-info.$ARCH.nix"
        '';

        in pkgs.mkShell {
          packages = with pkgs; [
            dig
            skopeo
            jq
            nix-prefetch-docker
            updatePiholeImageInfoScript
          ];
        };
    }
  );
}
