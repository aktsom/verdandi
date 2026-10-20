# contributing to Verdandi

issues and pull requests for Verdandi are welcome here, in this repository.

## how it was made

Verdandi's macOS layer (the window, audio routing, other apps as input, the AUv3, the
packaging: mostly `macos/` and `matron/src/platform/macos/`) was written with an AI coding
assistant, steered and tested by a person. the norns core (matron, crone, softcut, the lua
side) is the work of monome and the norns contributors, written by humans; the port changes
it as little as it can.

## what goes where

- Verdandi bugs, questions and ideas: the [issues](../../issues) here. please not on lines
  or at monome: they have nothing to do with this port.
- a fix to the norns core that is not about macOS belongs upstream, at
  [monome/norns](https://github.com/monome/norns), written and sent by you under their
  guidelines ([contributing-norns.md](contributing-norns.md)), including their rules on code
  assistants. please don't send code from this port there.

## pull requests here

- say what it fixes and how you tested it: which Mac, which macOS, which hardware
- keep it small and readable
- the macOS tests are in `macos/tests/` (see [readme-macos.md](readme-macos.md))

contributions are under the GPL-3.0, like the rest.
