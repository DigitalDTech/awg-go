# AWG Build

This repository packages the `amneziawg-go` and `amneziawg-tools` submodules
into a single Debian package named `ddt-awg` for Debian-based Linux
distributions.

It exists to replace the manual per-server build process. Instead of cloning
and compiling AmneziaWG separately on each Debian or Ubuntu host, this repo
builds reusable `.deb` packages in GitHub Actions so a server can be prepared
with a normal package install.

## Why this repo exists

- stop compiling AmneziaWG manually on each server
- produce one installable package that includes both `amneziawg-go` and the
  `amneziawg-tools` userland utilities
- build repeatable `amd64` and `arm64` Debian packages from CI
- keep the upstream projects as clean submodules instead of maintaining a fork
  with packaging changes mixed into them

## Outputs

Each package contains:

- `amneziawg-go`
- `awg`
- `awg-quick`
- bash completions
- man pages
- systemd unit files for `awg-quick`

When the kernel module is unavailable, `awg-quick` can fall back to the
included `amneziawg-go` userspace implementation, so the package is usable as a
single install for the userspace path.

## Minimum supported target distros

The CI-produced `.deb` packages target these minimum distro versions:

- Ubuntu 22.04 LTS or newer
- Debian 12 or newer

Architectures built by CI:

- `amd64`
- `arm64`

These minimums describe the packages produced by this repo's CI pipeline, not
every environment where the upstream projects might compile from source. If you
need older distributions than the list above, rebuild locally against an older
toolchain and libc baseline.

## CI build

The workflow at `.github/workflows/build-debian-packages.yml` builds `ddt-awg`
for:

- `amd64`
- `arm64`

Each run uploads the generated `.deb` files as GitHub Actions artifacts.

## Local build

On a Debian or Ubuntu build machine with Go 1.24.4 or newer available in
`PATH`:

```bash
sudo apt-get update
sudo apt-get install -y build-essential dpkg-dev fakeroot pkg-config systemd gcc-aarch64-linux-gnu
./packaging/build-deb.sh amd64
./packaging/build-deb.sh arm64
```

Artifacts are written to `dist/`.
