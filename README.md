# myenv-init

Bootstrap installer for [myenv](https://github.com/tanchihpin0517/myenv).

## Install

```bash
curl -fsSL https://tanchihpin0517.github.io/myenv-init/install.sh | bash
```

The script:

1. Prompts for a GitHub token (or reuses a saved one)
2. Writes `~/.myenv/config/settings.json` and `~/.myenv/config/token`
3. Installs the myenv binary to `~/.myenv/bin/myenv` (prebuilt download or local build)
4. Runs `myenv self install` to finish setup

### Options

Pass flags after `bash -s --` when piping:

```bash
curl -fsSL https://tanchihpin0517.github.io/myenv-init/install.sh | bash -s -- --binary-source source
```

| Flag | Values | Default | Description |
|------|--------|---------|-------------|
| `--binary-source` | `prebuilt`, `source` | `prebuilt` | How the myenv binary is installed |

This is saved to `~/.myenv/config/settings.json` as `binary_source`. `myenv self install` and `myenv sync` read it to decide how to install and update the binary.

- **`prebuilt`** — downloads the GitHub release binary for your platform; sync replaces it when a new release is detected
- **`source`** — downloads source at the latest release tag and runs `cargo build --release --locked`; sync rebuilds from source when a new release is detected (same digest check as prebuilt)

### Source build

Requires a Rust toolchain (`cargo`). Install from [rustup.rs](https://rustup.rs) if needed.

```bash
curl -fsSL https://tanchihpin0517.github.io/myenv-init/install.sh | bash -s -- --binary-source source
```

## Uninstall

```bash
curl -fsSL https://tanchihpin0517.github.io/myenv-init/uninstall.sh | bash
```

Or, after myenv is installed:

```bash
myenv self uninstall
```
