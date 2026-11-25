{
  description = "bib.nvim Neovim plugin";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
      version = (fromTOML (builtins.readFile ./.cz.toml)).tool.commitizen.version;
    in
    {
      packages = nixpkgs.lib.genAttrs systems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          grammars = pkgs.tree-sitter.withPlugins (
            p: with p; [
              tree-sitter-bibtex
              tree-sitter-latex
              tree-sitter-markdown
              tree-sitter-markdown-inline
              tree-sitter-yaml
            ]
          );
          parsers = pkgs.runCommand "bib-nvim-parsers" { } ''
            mkdir -p "$out/parser"
            for language in bibtex latex markdown markdown_inline yaml; do
              ln -s "${grammars}/$language.so" "$out/parser/$language.so"
            done
          '';
          plugin = pkgs.vimUtils.buildVimPlugin {
            pname = "bib-nvim";
            inherit version;
            src = pkgs.lib.cleanSourceWith {
              src = self;
              filter =
                path: _:
                !(builtins.elem (baseNameOf path) [
                  ".git"
                  ".devenv"
                  ".pre-commit-config.yaml"
                ]);
            };
            dependencies = [
              pkgs.vimPlugins.sqlite-lua
              parsers
            ];
            meta.license = pkgs.lib.licenses.asl20;
          };
        in
        {
          default = plugin;
          bib-nvim = plugin;
        }
      );
    };
}
