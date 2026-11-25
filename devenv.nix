{ pkgs, ... }:

let
  grammars = pkgs.tree-sitter.withPlugins (p: with p; [ tree-sitter-bibtex tree-sitter-latex tree-sitter-markdown tree-sitter-markdown-inline tree-sitter-yaml ]);
in
{
  languages.lua = {
    enable = true;
    package = pkgs.luajit;
    lsp.package = pkgs.lua-language-server;
  };

  packages = with pkgs; [
    commitizen
    git
    neovim
    nushell
    nufmt
    nu-lint
    stylua
    sqlite
    pandoc
  ];

  env = {
    MINI_NVIM = "${pkgs.vimPlugins.mini-nvim}";
    LD_LIBRARY_PATH = "${pkgs.sqlite.out}/lib";
    LIBSQLITE = "${pkgs.sqlite.out}/lib/libsqlite3.so";
    BIB_GRAMMARS = grammars;
    SQLITE_LUA = "${pkgs.vimPlugins.sqlite-lua}";
  };

  enterTest = "nu scripts/test.nu";

  git-hooks.hooks = {
    stylua.enable = true;
    nufmt.enable = true;
    nu-lint.enable = true;
    commitizen = {
      enable = true;
      name = "commitizen";
      entry = "${pkgs.commitizen}/bin/cz check --commit-msg-file";
      language = "system";
      stages = [ "commit-msg" ];
    };
    docs = {
      enable = true;
      name = "docs";
      entry = "${pkgs.coreutils}/bin/env MINI_NVIM=${pkgs.vimPlugins.mini-nvim} SQLITE_LUA=${pkgs.vimPlugins.sqlite-lua} BIB_GRAMMARS=${grammars} LIBSQLITE=${pkgs.sqlite.out}/lib/libsqlite3.so ${pkgs.neovim}/bin/nvim --headless --noplugin -u ./scripts/init.lua -c 'lua MiniDoc.generate({ \"lua/bib/init.lua\" }, \"doc/bib.txt\")' -c 'qa!'";
      files = "^lua/";
      pass_filenames = false;
      language = "system";
    };
  };
}
