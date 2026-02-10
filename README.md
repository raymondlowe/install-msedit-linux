# install-msedit-linux

## Why use this script?

The `edit` tool is not currently available in common Linux package managers (such as `apt`, `dnf`, or `yum`). This script provides a convenient and reliable way to always install the latest official release directly from Microsoft's GitHub repository, without waiting for distribution maintainers to package it.

## Overview

This project provides a simple shell script to install the latest release of Microsoft's [`edit`](https://github.com/microsoft/edit) command-line editor on Linux.

## Features
- Automatically fetches the latest release from GitHub
- Downloads and installs the correct Linux binary for your architecture
- Adds the binary to `~/.local/bin` (creating the directory if needed)
- Optionally updates your `PATH` in `~/.profile` if required
- Checks if `edit` is already installed and up-to-date, and only updates if a newer version is available
- **Optional:** Can set Microsoft `edit` as your default `edit` command (overriding `/usr/bin/edit`) with a flag
- Provides clear instructions to undo this change

## Installation

### 1. Install with a single command:
```sh
curl -fsSL https://raw.githubusercontent.com/raymondlowe/install-msedit-linux/main/install_msedit.sh | sh
```
- The script will:
  - Detect the latest version
  - Download and extract the binary
  - Place it in `~/.local/bin/edit`
  - Make it executable
  - Optionally update your `PATH` if needed
- After install, the script will tell you how to make Microsoft `edit` the default (see below).

### 2. (Optional) Make Microsoft `edit` the default `edit` command
If you want the Microsoft version to take precedence over `/usr/bin/edit`, run:
```sh
curl -fsSL https://raw.githubusercontent.com/raymondlowe/install-msedit-linux/main/install_msedit.sh | sh -s -- --set-default
```
- This creates a symlink at `~/bin/edit` pointing to the Microsoft binary.
- Make sure `~/bin` is in your `PATH` (the script will tell you if it isn't).

### 3. Undo (restore your previous default `edit`)
To remove the Microsoft `edit` as the default and restore your previous `edit` (e.g., `/usr/bin/edit`):
```sh
rm ~/bin/edit
```

### 4. Reload your shell (if the script updated your `PATH`):
```sh
source ~/.profile
```

### 5. Verify installation:
```sh
edit --version
```

## Requirements
- `curl`
- `awk`
- `tar`
- `zstd` or `unzstd` (for .tar.zst archives)
  - Install with: `sudo apt install zstd` (Debian/Ubuntu) or `sudo dnf install zstd` (Fedora/RHEL)
- `unxz` (for .xz archives)
- Standard POSIX `sh` (no bashisms required)
- **glibc 2.34+** (or whatever version the Microsoft binary requires)

> **Note:**
> The Microsoft `edit` binary may require a recent version of glibc (e.g., 2.34+). If you see errors about missing GLIBC versions when running `edit`, you may need to upgrade your Linux distribution to a newer release that includes a compatible glibc version.

## Notes
- The script is designed for x86_64 and aarch64 Linux systems.
- If you encounter issues, ensure you have the required tools installed.
- For more information about `edit`, see the [official repository](https://github.com/microsoft/edit).

---

*This project is not affiliated with Microsoft. It simply automates installation of their open source tool.*
