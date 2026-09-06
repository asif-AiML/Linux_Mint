# HP EliteBook 840 G6 Fingerprint Reader — Reproducible Setup Guide

This is the **known-good setup path** for the Synaptics fingerprint reader in the HP EliteBook 840 G6.

Hardware proven on this machine:

```text
USB ID: 06cb:00b7
Sensor: 57K0 FM-3439-001
Sensor type: 0x0d51
```

The goal of this file is **not** to document the investigation. It contains only the path that worked.

The setup is intentionally split into two phases:

- **Phase 1 — Native sensor support:** build the proven libfprint driver, provide the required Validity data, enroll a finger, and verify matching/rejection.
- **Phase 2 — System integration:** fprintd, normal-user USB access, PAM, sudo, login, lock screen, and suspend/resume validation. This section will be added only after those steps are proven.

---

# Phase 1 — Native sensor support

## 1. Install build dependencies

On Linux Mint 22.3 / Ubuntu Noble base:

```bash
sudo apt update
sudo apt install -y \
  git \
  python3-venv \
  build-essential \
  pkg-config \
  libglib2.0-dev \
  libgusb-dev \
  libusb-1.0-0-dev \
  libjson-glib-dev \
  libssl-dev \
  gobject-introspection
```

## 2. Clone the exact known-good libfprint source

Do **not** rely on whatever the latest upstream branch contains in the future.

The working source is libfprint MR !626 at this exact commit:

```text
0fd78560a245eebec1c93e71ee1f29b15ec1be67
```

Clone and pin it:

```bash
git clone https://gitlab.freedesktop.org/libfprint/libfprint.git
cd libfprint
git fetch origin merge-requests/626/head:mr-626
git switch mr-626
git checkout 0fd78560a245eebec1c93e71ee1f29b15ec1be67
cd ..
```

Check:

```bash
git -C libfprint rev-parse HEAD
```

Expected:

```text
0fd78560a245eebec1c93e71ee1f29b15ec1be67
```

## 3. Create the build tools environment

```bash
python3 -m venv tools-venv
source tools-venv/bin/activate
pip install meson ninja
```

The known-good test environment used Meson 1.12.0 and Ninja 1.13.2, but the libfprint source commit above is the important immutable anchor.

## 4. Build only the Validity driver

```bash
meson setup build libfprint -Ddrivers=validity -Ddoc=false
ninja -C build
```

The proven build completed with:

```text
[120/120]
```

**Do not run `ninja install` during Phase 1.**

## 5. Required Validity data

The reader requires device-specific data for `06cb:00b7` plus shared Validity data.

The proven device directory contains exactly:

```text
06cb_00b7/
├── init.bin
└── db_write_enable.bin
```

Known-good payload sizes before the 32-byte integrity trailer:

```text
init.bin               581 bytes payload / 613 bytes total
db_write_enable.bin   3621 bytes payload / 3653 bytes total
```

`init_clean_slate.bin` and `reset.bin` were **not required** for this machine and should not be added just because they exist for other devices.

The required shared files are:

```text
partition_sig_standard.bin
partition_sig_0090.bin
ca_pubkey.bin
tls_password.bin
gwk_sign.bin
fw_pubkey_x.bin
fw_pubkey_y.bin
```

These files came from `libfprint-validity-data` version `0.1.0`.

> The exact known-good binary files should be preserved alongside this project so a future reinstall does not depend on regenerated data or changing upstream sources. Once those artifacts are committed, use those preserved copies directly.

Expose the files under:

```text
/usr/local/share/libfprint/validity/
```

Resulting layout:

```text
/usr/local/share/libfprint/validity/
├── 06cb_00b7/
│   ├── init.bin
│   └── db_write_enable.bin
├── partition_sig_standard.bin
├── partition_sig_0090.bin
├── ca_pubkey.bin
├── tls_password.bin
├── gwk_sign.bin
├── fw_pubkey_x.bin
└── fw_pubkey_y.bin
```

During development these were reversible symlinks. For a clean reinstall, Phase 2 will define the final permanent installation layout.

## 6. Native enrollment test

From the directory containing `build/` and `libfprint/`:

```bash
source tools-venv/bin/activate
sudo env LD_LIBRARY_PATH="$PWD/build/libfprint" \
  ./build/examples/enroll
```

Choose the desired finger and follow the scan prompts.

Successful enrollment is confirmed by lines equivalent to:

```text
ENROLL_NUM_STATES completed successfully
Device reported enroll completion (... error: none)
Print for finger ... enrolled
```

The example creates:

```text
test-storage.variant
```

This is only the example program's local print reference; it is not the final fprintd/PAM storage mechanism.

## 7. Correct-finger verification

```bash
sudo env LD_LIBRARY_PATH="$PWD/build/libfprint" \
  ./build/examples/verify
```

Use the enrolled finger.

Expected result:

```text
MATCH!
```

## 8. Wrong-finger rejection test

Run the same verification command again:

```bash
sudo env LD_LIBRARY_PATH="$PWD/build/libfprint" \
  ./build/examples/verify
```

Use a different, non-enrolled finger.

Expected result:

```text
NO MATCH!
```

If both tests behave correctly, **Phase 1 is complete**.

---

# What is permanently known vs what may change

## Hardware / solution facts — treat these as stable

```text
USB ID                  06cb:00b7
Sensor                   57K0 FM-3439-001
Sensor type              0x0d51
Working libfprint commit 0fd78560a245eebec1c93e71ee1f29b15ec1be67
Required device blob     init.bin
Required DB blob         db_write_enable.bin
Validity data version    0.1.0
```

The 9a-family initialization and database-write-enable data used for the B7 directory were proven to work on this physical sensor.

## Things that may change over time

Do not build a future reinstall procedure around these mutable details:

- current upstream libfprint `master`
- the current state/name of MR !626
- newer libfprint-validity-data releases
- future Linux Mint/Ubuntu package versions
- future Meson/Ninja versions
- whether support eventually lands in distro libfprint

If newer distro packages eventually support `06cb:00b7` directly, prefer the native packaged solution. Until then, the exact commit and known-good data above are the reproducible fallback.

---

# Phase 2 — System-wide daily use

**Pending.**

Phase 2 will be written only after the following are tested successfully:

1. clean permanent installation strategy for the proven driver;
2. non-root USB permissions;
3. `fprintd-enroll` and `fprintd-verify`;
4. `sudo` authentication;
5. desktop login;
6. lock-screen unlock;
7. reboot persistence;
8. suspend/resume reliability;
9. rollback/uninstall procedure.

Until Phase 2 is completed, do not replace the distro libfprint and do not modify PAM based only on Phase 1.