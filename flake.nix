{
  description = "Pihole docker image & NixOS module for configuring a rootless pihole container (w/ port-forwarding)";

  inputs = {
    nixpkgs.url = "nixpkgs/nixpkgs-unstable";

    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }: with flake-utils.lib; eachSystem (with system; [ x86_64-linux aarch64-linux ]) (curSystem:
    let
      pkgs = nixpkgs.legacyPackages.${curSystem};

      imageName = "pihole/pihole";
      imageBaseInfo = import ./pihole-image-base-info.nix;
      imageInfo = {
        ${system.x86_64-linux}.pihole = imageBaseInfo // {
          arch = "amd64";
          sha256 = "sha256-5FUtafW2YdTfOfA0ieiyJasMUYEGReOMQ4PGZ8e32hY=";
        };

        ${system.aarch64-linux}.pihole = imageBaseInfo // {
          arch = "arm64";
          sha256 = "sha256-1gizGShpYT1IM3OzomTrHzoLWBejhOWmcLs52YauGzc=";
        };
      };

      piholeImage = pkgs.dockerTools.pullImage imageInfo.${curSystem}.pihole;

    in {
      packages = {
        inherit piholeImage;
        default = piholeImage;
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
            skopeo
            jq
            updatePiholeImageInfoScript
          ];

          inputsFrom = [ self.packages.${curSystem}.default ];
        };
    }
  );
}
