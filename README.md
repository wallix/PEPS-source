# PEPS-source

# About

Source code of [MLstate/PEPS](https://github.com/MLstate/PEPS), licensed under the AGPL. This repository contains the source code of PEPS, if you want to build it yourself or join the community.

If you just want to use and deploy PEPS, you may not need building from source but instead should go to [MLstate/PEPS](https://github.com/MLstate/PEPS) instead which contains the Docker container distribution directly.

# Building

To build PEPS, you need to:

- install [Opa](https://github.com/MLstate/opalang)
- install lessc (for instance through `npm -g install less`)
- generate style by typing `make style`
- compile PEPS by typing `make`
- install TLS certificates in `/etc/peps/server.key` and `/etc/peps/server.crt`
- launch with `./peps.exe`
- install required npm dependencies as told

# Contributing

We would love your contributions, and having an open development on GitHub is clearly a way to help building the PEPS community.
Please read CONTRIBUTING.md if you consider joining us!

# Contact

PEPS is a project created by [@henri_opa](https://twitter.com/henri_opa) at [MLstate](http://mlstate.com).
