{ pkgs, ... }:

let
  grammars = pkgs.tree-sitter.withPlugins (
    p: with p; [
      tree-sitter-bibtex
      tree-sitter-latex
      tree-sitter-markdown
      tree-sitter-markdown-inline
      tree-sitter-yaml
    ]
  );
in
{
  name = "bib";

  packages = with pkgs; [
    sqlite
    pandoc
  ];

  env = {
    LD_LIBRARY_PATH = "${pkgs.sqlite.out}/lib";
    LIBSQLITE = "${pkgs.sqlite.out}/lib/libsqlite3.so";
    BIB_GRAMMARS = grammars;
  };

  git-hooks.hooks = {
    sql-check = {
      enable = true;
      name = "SQL validate";
      entry = "${pkgs.sqlite}/bin/sqlite3 :memory: '.read'";
      files = "\\.sql$";
      language = "system";
    };
  };

  treefmt.config = {
    projectRootFile = "devenv.nix";
    programs.stylua.enable = true;
  };

  tasks = {
    "bib:test".exec =
      "${pkgs.neovim}/bin/nvim --headless --noplugin -u ./scripts/init.lua -c 'lua MiniTest.run()'";
    "bib:doc".exec =
      "${pkgs.neovim}/bin/nvim --headless --noplugin -u ./scripts/init.lua -c 'lua MiniDoc.generate()'";
  };
}
