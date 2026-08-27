{
  description = "CLI tool demo environment (tmux + vhs + wf-recorder + voiceover)";

  nixConfig = {
    extra-substituters = ["https://subbit-xyz.cachix.org"];
    extra-trusted-public-keys = ["subbit-xyz.cachix.org-1:nPswLlhI42dBqzVGfsBocI2WlpX5CpHYdCN2KEoedT8="];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    subbit-xyz.url = "github:kompact-io/subbit-xyz";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    subbit-xyz,
  }:
  # FIXME :: aiken flake broken on darwin builds. disable until fixed
  # flake-utils.lib.eachDefaultSystem (system: let
    flake-utils.lib.eachSystem ["x86_64-linux"] (system: let
      pkgs = import nixpkgs {inherit system;};
      lib = pkgs.lib;

      subbitPkgs = subbit-xyz.packages.${system};
      subbitBins = with subbitPkgs; [
        subbit-examples-echo-server
        subbit-examples-echo-client
        subbit-examples-echo-proxy
        subbit-index
        subbit-cli
        subbit-server
      ];

      tapeDir = ./tapes;
      tapeFiles =
        builtins.attrNames
        (lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".tape" n)
          (builtins.readDir tapeDir));

      mkTapeVideo = tapeFileName: let
        name = lib.removeSuffix ".tape" tapeFileName;
      in
        pkgs.stdenv.mkDerivation {
          pname = "tape-${name}";
          version = "0-unstable";
          # whole repo, since tapes reference ./tmux/echo.yaml etc by relative path
          src = lib.cleanSourceWith {
            src = ./.;
            filter = path: type:
              baseNameOf path != "out" && baseNameOf path != "result";
          };

          nativeBuildInputs =
            [pkgs.vhs pkgs.tmux pkgs.tmuxp pkgs.ffmpeg pkgs.bashInteractive pkgs.jq pkgs.yq-go pkgs.cacert pkgs.ncurses]
            ++ subbitBins;

          dontConfigure = true;

          buildPhase = ''
            runHook preBuild
            set -o pipefail
            export HOME="$TMPDIR"
            export VHS_NO_SANDBOX=true
            export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            mkdir -p out
            vhs "tapes/${tapeFileName}" 2>&1 | tee vhs.log
            [ -n "$(find out -type f -print -quit)" ] || { echo "error: vhs produced no output in out/" >&2; exit 1; }
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            mkdir -p "$out"
            cp -r out/. "$out"/
            runHook postInstall
          '';

          # vhs drives ttyd + a headless chromium (via rod). Chromium's own
          # sandbox can't set up inside nix's build sandbox, so we opt this
          # derivation out of it (see NixOS/nixpkgs#455564).
          __noChroot = true;

          meta.description = "Rendered video(s) for tapes/${tapeFileName}";
        };

      tapePackages =
        lib.listToAttrs
        (map
          (f: {
            name = "tape-${lib.removeSuffix ".tape" f}";
            value = mkTapeVideo f;
          })
          tapeFiles);

      allTapes = pkgs.symlinkJoin {
        name = "all-tapes";
        paths = builtins.attrValues tapePackages;
      };

      scripts = {
        record-tape = pkgs.writeShellApplication {
          name = "record-tape";
          runtimeInputs = [pkgs.vhs pkgs.tmux pkgs.tmuxp];
          meta.description = "Render a tape file: record-tape <tape-file>";
          text = ''
            if [ "$#" -ne 1 ]; then
              echo "usage: record-tape <tape-file>" >&2
              exit 1
            fi
            mkdir -p out
            echo "Rendering $1 ..."
            vhs "$1"
          '';
        };

        record-live = pkgs.writeShellApplication {
          name = "record-live";
          runtimeInputs = [pkgs.wf-recorder];
          meta.description = "Screen + mic, narrated live: record-live <output.mp4>";
          text = ''
            if [ "$#" -ne 1 ]; then
              echo "usage: record-live <output.mp4>" >&2
              exit 1
            fi
            echo "Recording screen + mic to $1. Ctrl-C to stop."
            wf-recorder -f "$1" --audio
          '';
        };

        record-narration = pkgs.writeShellApplication {
          name = "record-narration";
          runtimeInputs = [pkgs.wf-recorder];
          meta.description = "Mic-only narration track: record-narration <output.mp4>";
          text = ''
            if [ "$#" -ne 1 ]; then
              echo "usage: record-narration <output.mp4>" >&2
              exit 1
            fi
            echo "Recording mic-only narration to $1. Ctrl-C to stop."
            wf-recorder -f "$1" --audio --no-cursor -g "0,0 1x1"
          '';
        };

        build-site = pkgs.writeShellApplication {
          name = "build-site";
          runtimeInputs = [pkgs.jq pkgs.mustache-go pkgs.gawk pkgs.findutils pkgs.coreutils];
          meta.description = "Render site/index.mustache: build-site <videos-dir> <site-out-dir>";
          text = ''
            exec bash ${./scripts/build-site.sh} "$@" ${./site}
          '';
        };

        mux-voiceover = pkgs.writeShellApplication {
          name = "mux-voiceover";
          runtimeInputs = [pkgs.ffmpeg];
          meta.description = "Combine video + narration: mux-voiceover <video> <audio> <output.mp4>";
          text = ''
            if [ "$#" -ne 3 ]; then
              echo "usage: mux-voiceover <video-file> <audio-file> <output-file>" >&2
              exit 1
            fi
            video="$1"
            audio="$2"
            out="$3"
            ffmpeg -i "$video" -i "$audio" -c:v copy -c:a aac -shortest "$out"
            echo "Wrote $out"
          '';
        };
      };

      maxNameLen =
        lib.foldl' (acc: n:
          if lib.stringLength n > acc
          then lib.stringLength n
          else acc)
        0
        (lib.attrNames scripts);

      padRight = width: str:
        str + lib.concatStrings (lib.genList (_: " ") (width - lib.stringLength str));

      helpText = lib.concatStringsSep "\n" (
        ["  tmuxp load ./tmux/echo.yaml   # bring up the echo demo's pane layout"]
        ++ (lib.mapAttrsToList
          (name: drv: "  ${padRight maxNameLen name}   # ${drv.meta.description}")
          scripts)
      );
    in {
      devShells.default = pkgs.mkShell {
        packages = with pkgs;
          [
            bashInteractive # plain `bash` lacks readline (bind/complete); this fixes
            # "bind: command not found" when tmux/vhs spawn a bash shell
            tmux
            tmuxp
            vhs
            wf-recorder
            slurp
            asciinema
            ffmpeg
            yq-go # for the tomlset helper (config editing)
            jq # for parsing subbit-cli's JSON keyring output, and build-site
            mustache-go # for build-site (renders site/index.mustache)
          ]
          ++ subbitBins ++ builtins.attrValues scripts;

        shellHook = ''
          echo "cli-demo shell ready."
          echo "${helpText}"
        '';
      };

      apps =
        builtins.mapAttrs
        (name: drv: {
          type = "app";
          program = "${drv}/bin/${name}";
          meta.description = drv.meta.description;
        })
        scripts;

      packages = tapePackages // {all-tapes = allTapes;};
    });
}
