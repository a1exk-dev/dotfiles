# Agent guide

This file describes where to make documentation and configuration changes in this repository.

## Docs location

- All user-facing docs live in `_docs/`.
- Do not create new docs in module folders (for example, `zsh/`).
- Keep one doc per tool/topic in `_docs/`.
- If you need to add docs for a module, update the existing file in `_docs/`.
- Keep a root `ReadMe.md` with a table of contents linking to all `_docs/*.md` files.

## Zsh changes

- Config file: `zsh/.zshrc`
- Docs file: `_docs/03-zsh.md`
- Stow command (repo root): `stow --adopt -t "$HOME" zsh`

## Other modules

- Add module docs to `_docs/` using the next available number.
- Keep docs short, focused, and distro-agnostic when possible.
