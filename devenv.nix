{ pkgs, ... }:

{
  name = "bib";

  packages = with pkgs; [
    sqlite
    tree-sitter
  ];

  scripts = {
    test.exec = "${pkgs.neovim}/bin/nvim --headless --noplugin -u ./scripts/init.lua -c 'lua MiniTest.run()'";
    doc.exec = "${pkgs.neovim}/bin/nvim --headless --noplugin -u ./scripts/init.lua -c 'lua MiniDoc.generate({\"lua/bib/init.lua\"}, \"doc/bib.txt\")' -c 'qa!'";
  };
}
