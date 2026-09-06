# HP EliteBook 840 G6 Fingerprint Reader — Reproducible Setup Guide

This guide documents the **known-good, tested path** for enabling the built-in Synaptics fingerprint reader on an HP EliteBook 840 G6 running Linux Mint.

It is written so that:

- a future fresh Linux Mint install can be set up quickly;
- a beginner can follow it step by step;
- another person can reproduce the same working result;
- an AI assistant can read this folder and immediately understand the proven hardware, files, versions, and remaining work.

Do not treat this guide as a history of the investigation. Failed experiments and debugging details live in `Fingerprint_Reader_Path1_Progress.md`.

---

# Hardware this guide is for

Known-good machine:

```text
Laptop:      HP EliteBook 840 G6
USB device:  06cb:00b7
Sensor:      Synaptics / Validity 57K0 FM-3439-001
Sensor type: 0x0d51
```

The stock Linux Mint / Ubuntu Noble libfprint stack did not expose this sensor, but the native Validity driver from libfprint MR !626 worked successfully.

---

# Project status

The work is deliberately split into two phases.

## Phase 1 — Native sensor support

**COMPLETED AND PROVEN.**

This phase proves that the reader itself works natively under Linux:

- device detection;
- firmware communication;
- TLS/session setup;
- sensor calibration;
- real fingerprint capture;
- full fingerprint enrollment;
- correct-finger match;
- wrong-finger rejection.

## Phase 2 — System-wide daily use

**NOT COMPLETED YET.**

This will cover:

- permanent system installation;
- non-root USB access;
- `fprintd` integration;
- `sudo` authentication;
- desktop login;
- lock-screen unlock;
- reboot persistence;
- suspend/resume reliability;
- rollback/uninstall instructions.

Do not modify PAM or replace the system libfprint using only Phase 1 instructions.

---

# Files preserved in this repository

The dedicated fingerprint project folder is:

```text
FingerPrint_Sensor/
```

The intended permanent layout is:

```text
FingerPrint_Sensor/
├── README.md
├── Fingerprint_Reader_Setup_Guide.md
├── Fingerprint_Reader_Path1_Progress.md
└── permanent-data/
    └── validity/
        ├── SHA256SUMS
        ├── 06cb_00b7/
        │   ├── init.bin
        │   └── db_write_enable.bin
        ├── ca_pubkey.bin
        ├── fw_pubkey_x.bin
        ├── fw_pubkey_y.bin
        ├── gwk_sign.bin
        ├── partition_sig_0090.bin
        ├── partition_sig_standard.bin
        └── tls_password.bin
```

The `permanent-data/validity/` files are the exact known-good binary data used by the working sensor setup. They should be reused directly on future installs instead of being regenerated from changing upstream projects.

---

# Phase 1 — Fresh-install procedure

Follow these steps in order.

## Step 1 — Confirm the fingerprint reader is the expected device

Run:

```bash
lsusb | grep -i 06cb:00b7
```

Expected output should contain something similar to:

```text
06cb:00b7 Synaptics, Inc. Fingerprint reader
```

If `06cb:00b7` is not present, stop. This guide is specifically validated for that reader.

---

## Step 2 — Install the required build packages

Run:

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

If this command completes without an APT error, continue.

---

## Step 3 — Clone the exact libfprint version that was proven to work

Do **not** simply build the newest libfprint source and assume it behaves the same.

The known-good commit is:

```text
0fd78560a245eebec1c93e71ee1f29b15ec1be67
```

Run:

```bash
git clone https://gitlab.freedesktop.org/libfprint/libfprint.git
cd libfprint
git fetch origin merge-requests/626/head:mr-626
git switch mr-626
git checkout 0fd78560a245eebec1c93e71ee1f29b15ec1be67
cd ..
```

Verify the source revision:

```bash
git -C libfprint rev-parse HEAD
```

Expected exactly:

```text
0fd78560a245eebec1c93e71ee1f29b15ec1be67
```

If the value differs, do not continue until the checkout is corrected.

---

## Step 4 — Create the build-tools environment

Run:

```bash
python3 -m venv tools-venv
source tools-venv/bin/activate
pip install meson ninja
```

The original successful environment used:

```text
Meson 1.12.0
Ninja 1.13.2
```

Those versions are useful reference points, but the exact libfprint commit above is the more important reproducibility anchor.

---

## Step 5 — Build only the Validity driver

Run:

```bash
meson setup build libfprint -Ddrivers=validity -Ddoc=false
ninja -C build
```

The original successful build ended at:

```text
[120/120]
```

The exact task count may vary with tooling, but the build must finish successfully with no fatal error.

**Do not run `ninja install` during Phase 1.**

---

## Step 6 — Verify the preserved Validity files

From the root of the `FingerPrint_Sensor` folder, run:

```bash
cd permanent-data/validity
sha256sum -c SHA256SUMS
cd ../..
```

All nine entries should end in:

```text
OK
```

Known-good SHA-256 values:

```text
943569128f8190481ba32c06276e2f9912324a60f882b4a0102c0224f259a680  permanent-data/validity/06cb_00b7/db_write_enable.bin
a2d545c2d69c3657f06d3583e95c17caea25ba62fdab8ea7bb194d2b7c92f4c4  permanent-data/validity/06cb_00b7/init.bin
edc24214c954d40cce650b3896c7d4c8c6e73b479ddac830213ca05e731c93ab  permanent-data/validity/ca_pubkey.bin
bee4814c74c5f1effe5dc26772c7531dbb1a14c70647cb8a14c8233a1cd0a72a  permanent-data/validity/fw_pubkey_x.bin
38a4e723c82fee10ae48564294f16a3542294b1f0415ffaaf99b7a1ffa7af3d2  permanent-data/validity/fw_pubkey_y.bin
2d5206dd6fbdb62a8d04fa46f13219bfafe2dd8e2e09b21606f6c0fc87c8429c  permanent-data/validity/gwk_sign.bin
1a7b19fda262fd6b9779c0f94491f3a059489e529e6ad6d15853b501cbe7c822  permanent-data/validity/partition_sig_0090.bin
42e7cb9afc2ead80b4c1e2edfc12db4f79a4c652f32327e899a46f849eb2c0da  permanent-data/validity/partition_sig_standard.bin
9bccbf4b561a4c3dda02a4dfd93c8fc5d12bcc46899b3b9ddd2d71a446941965  permanent-data/validity/tls_password.bin
```

If any file reports `FAILED`, stop. Do not use a corrupted or modified blob.

---

## Step 7 — Expose the Validity data to libfprint

The tested driver searches under:

```text
/usr/local/share/libfprint/validity/
```

Create the directory:

```bash
sudo mkdir -p /usr/local/share/libfprint/validity/06cb_00b7
```

Copy the device-specific files:

```bash
sudo cp permanent-data/validity/06cb_00b7/init.bin \
        permanent-data/validity/06cb_00b7/db_write_enable.bin \
        /usr/local/share/libfprint/validity/06cb_00b7/
```

Copy the shared Validity files:

```bash
sudo cp \
  permanent-data/validity/partition_sig_standard.bin \
  permanent-data/validity/partition_sig_0090.bin \
  permanent-data/validity/ca_pubkey.bin \
  permanent-data/validity/tls_password.bin \
  permanent-data/validity/gwk_sign.bin \
  permanent-data/validity/fw_pubkey_x.bin \
  permanent-data/validity/fw_pubkey_y.bin \
  /usr/local/share/libfprint/validity/
```

Do **not** add `reset.bin` or `init_clean_slate.bin`. They were not required for this hardware.

---

## Step 8 — Run the native enrollment test

Run this from the directory that contains `build/` and `libfprint/`:

```bash
source tools-venv/bin/activate
sudo env LD_LIBRARY_PATH="$PWD/build/libfprint" \
  ./build/examples/enroll
```

Choose the finger you want to enroll and follow the prompts.

The known-good test used the **right index finger**.

Successful enrollment is confirmed by output equivalent to:

```text
ENROLL_NUM_STATES completed successfully
Device reported enroll completion (... error: none)
Print for finger FP_FINGER_RIGHT_INDEX enrolled
```

The example should also create:

```text
test-storage.variant
```

That file belongs only to the libfprint example test. It is not the final system-wide fingerprint database.

---

## Step 9 — Verify the enrolled finger

Run:

```bash
sudo env LD_LIBRARY_PATH="$PWD/build/libfprint" \
  ./build/examples/verify
```

Touch the same finger that was enrolled.

Expected:

```text
MATCH!
```

The original successful run also reported that the right index finger matched successfully.

---

## Step 10 — Test rejection with a different finger

Run the same command again:

```bash
sudo env LD_LIBRARY_PATH="$PWD/build/libfprint" \
  ./build/examples/verify
```

This time deliberately use a different, non-enrolled finger.

Expected:

```text
NO MATCH!
```

If the enrolled finger gives `MATCH!` and a different finger gives `NO MATCH!`, Phase 1 is successfully reproduced.

---

# What is stable and what may change

This distinction is important for future maintenance.

## Stable known-good facts

Treat these as the frozen fallback configuration:

```text
USB ID                  06cb:00b7
Sensor                   57K0 FM-3439-001
Sensor type              0x0d51
Working libfprint commit 0fd78560a245eebec1c93e71ee1f29b15ec1be67
Required device file     init.bin
Required DB file         db_write_enable.bin
Shared Validity files    7 files listed above
```

The preserved binary bundle in `permanent-data/validity/` is part of this known-good configuration.

## Things that may change in the future

These should never be assumed to stay identical:

- libfprint `master`;
- MR !626 branch state;
- newer libfprint commits;
- Linux Mint / Ubuntu package versions;
- Meson / Ninja versions;
- upstream Validity-data projects;
- package dependency names in future distributions;
- whether Linux Mint eventually ships direct support for `06cb:00b7`.

If a future Linux Mint release supports `06cb:00b7` directly through its normal packaged libfprint, prefer the distro-native implementation. Keep this guide as the proven fallback.

---

# For AI assistants reading this repository

If you are an AI assistant helping with this project:

1. Read `README.md` first for the current high-level state.
2. Use this file for the known-good reproduction procedure.
3. Use `Fingerprint_Reader_Path1_Progress.md` only when historical debugging context is needed.
4. Do not suggest regenerating the Validity binary files unless the preserved bundle is missing or verified corrupt.
5. Do not replace the system libfprint or modify PAM based only on Phase 1.
6. The native driver itself is already proven functional; do not restart hardware-support investigation unless new evidence shows regression.
7. Phase 2 should be approached as system integration of a proven driver, not as another sensor reverse-engineering task.

---

# Phase 2 — System-wide daily use

**Pending.**

This section will be added only after each step is tested successfully on the real machine.

Planned validation order:

1. safe permanent installation strategy for the proven libfprint build;
2. normal non-root USB access;
3. `fprintd-enroll`;
4. `fprintd-verify`;
5. `sudo` authentication;
6. desktop login;
7. lock-screen unlock;
8. reboot persistence;
9. suspend/resume reliability;
10. rollback / uninstall procedure.

Until then, Phase 1 proves that the hardware and native driver work, but it is not yet the daily-use system configuration.