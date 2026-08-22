{
  description = "CLI tool demo environment (tmux + vhs + wf-recorder + voiceover)";

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
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {inherit system;};
      lib = pkgs.lib;

      subbitPkgs = subbit-xyz.packages.${system};
      # real bin names on PATH once in the shell: echo-server, echo-client,
      # echo-proxy, mock-index (+ naive-index), subbit-cli, subbit-server —
      # no aliasing, no per-call `nix shell ... -c ...` wrapping/lag.
      subbitBins = with subbitPkgs; [
        subbit-examples-echo-server
        subbit-examples-echo-client
        subbit-examples-echo-proxy
        subbit-index
        subbit-cli
        subbit-server
      ];

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
            jq # for parsing subbit-cli's JSON keyring output
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
    });
}
