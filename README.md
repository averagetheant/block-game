# block-game

A Roblox game built on [Boil](https://github.com/REALEncryptal/Boil) — Rojo + Wally + React
(jsdotlua) in a Feature-Sliced Design layout, with a Lune splitter that routes
colocated feature code to the right Roblox service at sync time.

## Getting started

```bash
rokit install                     # rojo, wally, lune
wally install                     # populate Packages/

lune run tools/split -- --watch   # terminal 1 — rebuild build/ on change
rojo serve                        # terminal 2 — sync to Studio
```

Then connect from Studio's Rojo plugin.

## Adding features and skins

```bash
boil explore                      # browse the index and install
boil add <owner>/<package>
```

Install the CLI once with `npm i -g @encryptal/boil`.

## Docs

`docs/` carries the framework's own documentation — the architecture, the file
naming rules, the four UI seams, and the package registry. Start with
`docs/README.md`.
