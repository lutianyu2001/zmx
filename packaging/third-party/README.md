# Third-party licenses

The zmx binary is statically linked. These are the license texts of the code compiled into it, which `zig build
release` puts into every release archive next to zmx's own `LICENSE`.

| Directory  | Project                                                         | Version                          | License                                  |
| ---------- | --------------------------------------------------------------- | -------------------------------- | ---------------------------------------- |
| `ghostty/` | [Ghostty](https://github.com/ghostty-org/ghostty) (libghostty-vt) | `22f100c` (see `build.zig.zon`) | MIT                                      |
| `uucode/`  | [uucode](https://github.com/jacobsandlund/uucode)               | `ea62149` (pinned by Ghostty)    | MIT; Unicode-3.0 (UCD data); Hoehrmann's UTF-8 decoder (MIT) |
| `simdutf/` | [simdutf](https://github.com/simdutf/simdutf), vendored by Ghostty | 9.0.0                          | Apache-2.0 OR MIT                        |
| `highway/` | [Highway](https://github.com/google/highway)                    | `66486a1` (pinned by Ghostty)    | Apache-2.0 OR BSD-3-Clause               |
| `wuffs/`   | [Wuffs](https://github.com/google/wuffs)                        | `7411f48` (pinned by Ghostty)    | Apache-2.0 and MIT                       |
| `zig/`     | [Zig](https://codeberg.org/ziglang/zig) standard library and compiler-rt | 0.17.0                  | MIT                                      |
| `musl/`    | [musl](https://musl.libc.org/), shipped with Zig (Linux builds) | as in Zig 0.17.0                 | MIT                                      |

translate-c, also in `build.zig.zon`, only runs at build time and leaves no code in the binary.

When `build.zig.zon` or the Zig version changes, check which packages the release binary pulls in (the source paths
in its debug info, `strings zmx | grep zig-pkg/`) and update these files from the new versions.
