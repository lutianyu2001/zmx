<h1>
<p align="center">
  <img src="./logo.png" alt="Logo" width="128">
  <br>zmx
</h1>
<p align="center">
  Session attach/detach for the terminal.
  <br />
  <a href="https://zmx.sh">Docs</a>
  ·
  <a href="https://bower.sh/you-might-not-need-tmux">You might not need tmux</a>
  ·
  Sponsored by <a href="https://pico.sh">pico.sh</a>
</p>

## features

- Persist terminal shell sessions
- Ability to attach and detach from a shell session without it being killed
- Native terminal scrollback
- Multiple clients can connect to the same session
- Re-attaching to a session restores previous terminal state and output
- Send commands to a session without attaching to it
- Print scrollback history of a terminal session in plain text
- Works on mac and linux
- Use `zmx` as a zig package
- This project does **NOT** provide windows, tabs, or splits

## install

This fork's releases are packaged in [q0wkp/pkgs](https://github.com/q0wkp/pkgs), whose README says how to add its
repositories to pacman and Pacstall:

| System | Release | Built from Git |
| --- | --- | --- |
| Arch Linux | `sudo pacman -Syu zmx-bin` | `zmx-git`, with makepkg |
| Ubuntu, Debian | `pacstall -I zmx-bin` | `pacstall -I zmx-git` |
| macOS, with Homebrew | `brew install q0wkp/tap/zmx` | `brew install --HEAD q0wkp/tap/zmx-git` |

With Homebrew, run `brew tap q0wkp/tap` and `brew trust q0wkp/tap` once before installing: without the second, some
versions of Homebrew refuse a package of the tap that names another one.

The packages built from Git build the main branch on your own machine, to try a change before it is released. They
take the released package's place and stay until you install that one again: see
[Building from Git](https://github.com/q0wkp/pkgs#building-from-git) there for how to change over and back.

## demos

- [zmx - intro](https://youtu.be/UIXj0_rhPgI)
- [zmx - ai portal](https://youtu.be/CV3skPYHP4Q)

## docs

Full documentation is available at **[https://zmx.sh](https://zmx.sh)**:

- [Install & Usage](https://zmx.sh/getting-started)
- [Shell Integration](https://zmx.sh/shell-integration)
- [SSH Workflow](https://zmx.sh/ssh)
- [Zig Package](https://zmx.sh/zig-package)
- [Configuration & Debugging](https://zmx.sh/configuration)
- [Architecture & Philosophy](https://zmx.sh/architecture)
- [Community Tools](https://zmx.sh/community)

## build

Requires Zig `v0.17.0`:

```bash
# Build debug binary (./zig-out/bin/zmx)
zig build

# Install release binary to ~/.local/bin
zig build -Doptimize=ReleaseSafe --prefix ~/.local
```

See [CONTRIBUTING.md](./CONTRIBUTING.md) for testing, local debugging, and contribution guidelines.
