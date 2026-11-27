## v1.1.1 (2026-11-27)
### Fixes
- skip spell checking on citation keys ([0899db5](https://github.com/phrmendes/bib.nvim/commit/0899db5e55356302dfd9e59209dba75ad7eff64a))

## v1.1.0 (2026-11-27)
### Features
- add bibliography health checks ([ed1c1fc](https://github.com/phrmendes/bib.nvim/commit/ed1c1fc6784a68db7c16979e6e10b2650ec41e4b))
### Fixes
- preserve bibliography and Zotero state ([b6e7143](https://github.com/phrmendes/bib.nvim/commit/b6e71433735270fd6beee68aa5f8c3a457fd6466))
- resolve citations in Markdown and LaTeX ([24e0cf0](https://github.com/phrmendes/bib.nvim/commit/24e0cf016783a817ffb24f08da07502dff232c5a))
- avoid concealing citations in code ([50a41e0](https://github.com/phrmendes/bib.nvim/commit/50a41e0ad0392eae030d4a408381eb1f2398831d))

## v1.0.0 (2026-11-25)
### Features
- prepare v1.0.0 release ([3e57e40](https://github.com/phrmendes/bib.nvim/commit/3e57e40902af8afa5e53eb47cdf8fc4ed0ec4f91))
- auto-generated docs, code fence conceal skip, Apache 2.0 license ([376621b](https://github.com/phrmendes/bib.nvim/commit/376621b4b48227fe266cd8c7eb0fb809afed590a))
- code actions for PDF and notes, test coverage ([59b9477](https://github.com/phrmendes/bib.nvim/commit/59b9477ce7bb61f3c42a28da03a5182888ec7fb1))
- polish picker, conceal, completion, roadmap ([c04d971](https://github.com/phrmendes/bib.nvim/commit/c04d971cc6d67c5d667f294b0d52fea12fc91a30))
- async search with vim.ui.select via async.nvim ([d8c37b1](https://github.com/phrmendes/bib.nvim/commit/d8c37b15cfbce6893f27064224228f442f72a29c))
- Zotero backend — load, match, get, definition, hover ([8e20b69](https://github.com/phrmendes/bib.nvim/commit/8e20b698029e7d57d85fea46a7cfdfb4ee0525b0))
- utils.find_zotero_db with config override ([4d7d6de](https://github.com/phrmendes/bib.nvim/commit/4d7d6de54b87b9ceb4834e95334f74b43c99ef3f))
### Fixes
- **zotero**: copy db to temp to avoid lock, surface backend errors to lsp.log ([3650c50](https://github.com/phrmendes/bib.nvim/commit/3650c505445a7e9ccc95380598ab1f4297b213be))
- **lsp**: signal on_exit on exit, fix shutdown, proper is_closing/terminate ([b1e89e9](https://github.com/phrmendes/bib.nvim/commit/b1e89e9949846f8145893934905f048aac79d3a4))
- **conceal**: scope to configured filetypes via FileType autocmd ([0a4ada7](https://github.com/phrmendes/bib.nvim/commit/0a4ada74606da32a2827e482bd2a4727b930ef3a))
- **lsp**: remove broken LspAttach pattern, unify conceal for bib/zotero, extract regex to patterns ([69f67e8](https://github.com/phrmendes/bib.nvim/commit/69f67e880f38bae95158a0fb10daf94e54982087))
- replace async.nvim with vim.schedule ([e4685b4](https://github.com/phrmendes/bib.nvim/commit/e4685b48ee818a73f64eb96647e5d12c3e75709a))
- move async.wrap inside coroutine ([3d09d7e](https://github.com/phrmendes/bib.nvim/commit/3d09d7ee9544d4ba8bbe3b33c6a7ba160fa40817))
- async.wrap(argc, func) signature ([eefc486](https://github.com/phrmendes/bib.nvim/commit/eefc4866c1651c3b6fe45121350fcfd05d5783b4))
- break circular dependency in utils/backends ([43c5b2c](https://github.com/phrmendes/bib.nvim/commit/43c5b2cddd9683f6443728f6dd05def3a96ef5b7))
- add SQL validate pre-commit hook ([f173548](https://github.com/phrmendes/bib.nvim/commit/f1735483283b08eedc0222539f6c7f31cfc95d0c))
- remove redundant stylua from packages (git-hooks handles it) ([3a67fec](https://github.com/phrmendes/bib.nvim/commit/3a67fecaf0d78413c0f406fabd0fa40bbb53e347))
### Refactoring
- **tests**: DRY helpers, rename tu→u, fix duplicate assertion ([997725f](https://github.com/phrmendes/bib.nvim/commit/997725f31ce69f1ef1ef81e0e9c71cde5b004aac))
- standards-aligned rewrite ([b81cc8d](https://github.com/phrmendes/bib.nvim/commit/b81cc8dce2298f5b80779d01caeb956ea6a94209))
- :Bib search with zotero keyword, open-on-select ([2769252](https://github.com/phrmendes/bib.nvim/commit/27692526e7686a8c6ee8851bc017e709e8268999))
- lazy-load single-use imports to break startup chain ([0c48059](https://github.com/phrmendes/bib.nvim/commit/0c480597c0668e999088bfcf88ba76f1f6f043c9))
- directory modules, constants, patterns, conceal, tests ([df2e89a](https://github.com/phrmendes/bib.nvim/commit/df2e89ac37f273867f1612e99cdcb19d005f2c49))
- extract patterns.lua, use nix parsers, remove biblatex ([7a8660f](https://github.com/phrmendes/bib.nvim/commit/7a8660fa1ebe90ce709885aea3a4d47a589ecd3a))
