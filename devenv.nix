{ inputs, pkgs, ... }:

let
  grammars = pkgs.tree-sitter.withPlugins (p: with p; [
    tree-sitter-bibtex
    tree-sitter-latex
    tree-sitter-markdown
    tree-sitter-markdown-inline
    tree-sitter-yaml
  ]);
in
{
  name = "bib";

  packages = with pkgs; [
    sqlite
  ];

  env = {
    LIBSQLITE = "${pkgs.sqlite.out}/lib/libsqlite3.so";
    BIB_GRAMMARS = grammars;
  };

  git-hooks.hooks = {
    stylua.enable = true;
  };

  scripts = {
    test.exec = "${pkgs.neovim}/bin/nvim --headless --noplugin -u ./scripts/init.lua -c 'lua MiniTest.run()'";
    doc.exec = "${pkgs.neovim}/bin/nvim --headless --noplugin -u ./scripts/init.lua -c 'lua MiniDoc.generate({\"lua/bib/init.lua\"}, \"doc/bib.txt\")' -c 'qa!'";
  };
}
