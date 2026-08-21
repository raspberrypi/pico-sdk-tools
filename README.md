# Pico SDK Tools

This repository is used to provide pre-built binaries of the SDK tools for Windows, macOS, Raspberry Pi OS, and other Linux operating systems (builds performed on Ubuntu).
These binaries are primarily for use by the [pico-vscode](https://github.com/raspberrypi/pico-vscode) extension, and the release format is subject to change at any time.

The tools currently included are:
* **picotool**
* **OpenOCD** (includes `linuxgpiod` and `cmsis-dap` adapters)
* **pioasm**
* **RISC-V Toolchain**

## Installing the tools

[`installer/`](installer) holds a script that downloads these tools, plus the
Arm toolchain, CMake and ninja, into `~/.pico-sdk` — the same layout the
pico-vscode extension uses — and puts them on `PATH`:

It needs Python 3.9 or newer and nothing else, and `git` if you want it to clone
the SDK too:

```bash
./installer/install_pico_tools.py 2.3.0 --platform linux_arm64
```

It is also a composite action, so a GitHub Actions job can install the same set
of tools in one step:

```yaml
- uses: raspberrypi/pico-sdk-tools/installer@main
  with:
    sdk-version: '2.3.0'
```

See [`installer/README.md`](installer/README.md) for the full options.
