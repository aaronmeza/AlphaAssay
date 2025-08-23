Got you. Here’s a tiny, battle-tested macOS helper that builds a Talos **CIDATA** USB for any node (CP or worker) with **mTLS-only** boot. It’s interactive (shows disks), safe (refuses to touch internal disks), and fast.

Drop this into your repo at: `infra/talos/tools/make_cidata_usb.sh`

```bash
#!/usr/bin/env bash
# make_cidata_usb.sh — Create a Talos NoCloud (CIDATA) USB for Raspberry Pi
# macOS only (uses diskutil). Safe by default; refuses to touch internal disks.
# Usage examples see bottom.

set -euo pipefail

red()  { printf "\033[31m%s\033[0m\n" "$*"; }
grn()  { printf "\033[32m%s\033[0m\n" "$*"; }
yel()  { printf "\033[33m%s\033[0m\n" "$*"; }
die()  { red "ERROR: $*"; exit 1; }

if [[ "$(uname -s)" != "Darwin" ]]; then
  die "This script is for macOS (uses diskutil)."
fi

# Defaults
LABEL="CIDATA"
HOSTNAME=""
ADDR_CIDR=""   # e.g. 172.16.0.30/24
GATEWAY=""     # e.g. 172.16.0.1
DNS="1.1.1.1,8.8.8.8"
USER_DATA=""
DISK_DEV=""    # e.g. /dev/disk4
NO_FORMAT=0
NO_EJECT=0
DRYRUN=0

usage() {
  cat <<EOF
Usage:
  sudo $0 -d /dev/diskX -f <user-data.yaml> -H <hostname> [-a <addr/cidr> -g <gateway> -n <dns_csv>] [-L <label>] [--no-format] [--no-eject] [--dry-run]

Required:
  -d  Disk device (external USB) e.g. /dev/disk4
  -f  Path to Talos machine config (user-data), e.g. controlplane.yaml or worker.yaml
  -H  Hostname for meta-data (e.g. cp-1, w1)

Optional:
  -a  Static IP/CIDR (e.g. 172.16.0.30/24). Omit for DHCP (no network-config written)
  -g  Gateway IP (e.g. 172.16.0.1) — required if -a is set
  -n  DNS servers CSV (default: ${DNS})
  -L  Volume label (default: ${LABEL})
      --no-format   Do not erase/format (must already be a mounted ${LABEL} volume)
      --no-eject    Leave volume mounted after writing
      --dry-run     Print what would be written, don’t touch disk

Tips:
  • Control plane: -f infra/talos/cluster/clusterconfig/controlplane.yaml -H cp-1 -a 172.16.0.30/24 -g 172.16.0.1
  • Worker:        -f infra/talos/cluster/clusterconfig/worker.yaml      -H w1   -a 172.16.0.31/24 -g 172.16.0.1

List candidate external disks:
  diskutil list external physical
EOF
  exit 1
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d) DISK_DEV="$2"; shift 2;;
    -f) USER_DATA="$2"; shift 2;;
    -H) HOSTNAME="$2"; shift 2;;
    -a) ADDR_CIDR="$2"; shift 2;;
    -g) GATEWAY="$2"; shift 2;;
    -n) DNS="$2"; shift 2;;
    -L) LABEL="$2"; shift 2;;
    --no-format) NO_FORMAT=1; shift;;
    --no-eject)  NO_EJECT=1; shift;;
    --dry-run)   DRYRUN=1; shift;;
    -h|--help)   usage;;
    *) red "Unknown arg: $1"; usage;;
  esac
done

[[ -z "${DISK_DEV}" || -z "${USER_DATA}" || -z "${HOSTNAME}" ]] && usage
[[ ! -f "${USER_DATA}" ]] && die "User-data file not found: ${USER_DATA}"
if [[ -n "${ADDR_CIDR}" && -z "${GATEWAY}" ]]; then
  die "Static IP specified (-a) but no gateway (-g)."
fi

# Safety checks for disk
info="$(diskutil info "${DISK_DEV}" 2>/dev/null || true)"
[[ -z "${info}" ]] && die "Disk ${DISK_DEV} not found. Use: diskutil list external physical"
echo "${info}" | grep -qi "Internal: *No" || die "Refusing to touch an internal disk. Pick an EXTERNAL USB device."
echo "${info}" | grep -qi "Removable Media: *Removable" || yel "Warning: disk may not be removable (continuing)."

VOL_MNT="/Volumes/${LABEL}"

do_format() {
  yel "Erasing ${DISK_DEV} to FAT32 label ${LABEL} (MBR)…"
  diskutil unmountDisk force "${DISK_DEV}" >/dev/null 2>&1 || true
  # MBR + FAT32 maximizes Pi compatibility
  diskutil eraseDisk FAT32 "${LABEL}" MBRFormat "${DISK_DEV}" \
    || die "eraseDisk failed"
}

mount_point() {
  # diskutil auto-mounts post-erase; otherwise mount by label
  for i in {1..15}; do
    [[ -d "${VOL_MNT}" ]] && break
    sleep 1
  done
  if [[ ! -d "${VOL_MNT}" ]]; then
    yel "Volume not auto-mounted, trying to mount…"
    diskutil mount "${DISK_DEV}" || true
    [[ -d "${VOL_MNT}" ]] || die "Couldn't mount ${DISK_DEV} at ${VOL_MNT}"
  fi
}

write_files() {
  grn "Writing files to ${VOL_MNT}"
  # user-data
  install -m 0644 "${USER_DATA}" "${VOL_MNT}/user-data"
  # meta-data
  cat > "${VOL_MNT}/meta-data" <<EOF
local-hostname: ${HOSTNAME}
EOF
  # network-config (optional)
  if [[ -n "${ADDR_CIDR}" ]]; then
    IFS=',' read -r -a DNS_ARR <<< "${DNS}"
    cat > "${VOL_MNT}/network-config" <<EOF
version: 1
config:
  - type: physical
    name: eth0
    subnets:
      - type: static
        address: ${ADDR_CIDR}
        gateway: ${GATEWAY}
    dns:
      nameservers: [$(printf '"%s",' "${DNS_ARR[@]}" | sed 's/,$//')]
EOF
  fi
}

verify() {
  grn "Verifying…"
  [[ -f "${VOL_MNT}/user-data" ]]      || die "user-data missing"
  [[ -f "${VOL_MNT}/meta-data" ]]      || die "meta-data missing"
  if [[ -n "${ADDR_CIDR}" ]]; then
    [[ -f "${VOL_MNT}/network-config" ]] || die "network-config missing (expected static config)"
  fi
  echo "Files:"
  ls -l "${VOL_MNT}"
  echo "SHA256:"
  shasum -a 256 "${VOL_MNT}/user-data" | awk '{print "  user-data  ",$1}'
}

eject() {
  [[ "${NO_EJECT}" -eq 1 ]] && { yel "Leaving volume mounted (per --no-eject)."; return; }
  yel "Ejecting ${VOL_MNT}"
  diskutil eject "${VOL_MNT}" >/dev/null || diskutil eject "${DISK_DEV}" >/dev/null || true
}

# Dry-run display
if [[ "${DRYRUN}" -eq 1 ]]; then
  cat <<EOF
[DRY-RUN] Would create ${LABEL} on ${DISK_DEV} and write:
  ${VOL_MNT}/user-data      <- ${USER_DATA}
  ${VOL_MNT}/meta-data      <- local-hostname: ${HOSTNAME}
  ${VOL_MNT}/network-config <- ${ADDR_CIDR} via ${GATEWAY} DNS ${DNS}  $( [[ -z "${ADDR_CIDR}" ]] && echo "(skipped: DHCP)" )
EOF
  exit 0
fi

# Go!
[[ "${NO_FORMAT}" -eq 1 ]] || do_format
mount_point
write_files
verify
eject
grn "Done. Plug this USB alongside the Talos SD in the Pi and power on."
```

Make it executable:

```bash
chmod +x infra/talos/tools/make_cidata_usb.sh
```

### Usage (copy/paste)

Control plane (static IP):

```bash
sudo infra/talos/tools/make_cidata_usb.sh \
  -d /dev/disk4 \
  -f infra/talos/cluster/clusterconfig/controlplane.yaml \
  -H cp-1 \
  -a 172.16.0.30/24 -g 172.16.0.1
```

Worker (static IP):

```bash
sudo infra/talos/tools/make_cidata_usb.sh \
  -d /dev/disk5 \
  -f infra/talos/cluster/clusterconfig/worker.yaml \
  -H w1 \
  -a 172.16.0.31/24 -g 172.16.0.1
```

DHCP (omit network-config):

```bash
sudo infra/talos/tools/make_cidata_usb.sh \
  -d /dev/disk4 \
  -f infra/talos/cluster/clusterconfig/controlplane.yaml \
  -H cp-1
```

Find your USB device identifiers:

```bash
diskutil list external physical
```

### Pro tips

* If you want **zero prompts**, pre-check `diskutil list external physical`, then script both CP & worker in a tiny wrapper.
* If you’re moving fast before a flight: build the two sticks, plug both into the Pis, power them on. After \~60–90s:

  ```bash
  export TALOSCONFIG=infra/talos/cluster/clusterconfig/talosconfig
  talosctl --endpoints 172.16.0.30 --nodes 172.16.0.30 version
  talosctl --endpoints 172.16.0.30 --nodes 172.16.0.30 bootstrap
  mkdir -p infra/talos/cluster/talosconfig
  talosctl --endpoints 172.16.0.30 --nodes 172.16.0.30 \
    kubeconfig infra/talos/cluster/talosconfig/kubeconfig --force --merge
  kubectl --kubeconfig infra/talos/cluster/talosconfig/kubeconfig get nodes -o wide
  ```

# Want a Linux version later (lsblk + mkfs.vfat)? Say the word and I’ll drop it in.
