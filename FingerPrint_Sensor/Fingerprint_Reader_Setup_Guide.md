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

## Phase 1 — Native sensor support

**COMPLETE AND PROVEN.**

The reader works natively under Linux at the libfprint level:

- device detection;
- firmware communication;
- TLS/session setup;
- sensor calibration;
- real fingerprint capture;
- full fingerprint enrollment;
- correct-finger match;
- wrong-finger rejection.

## Phase 2 — System-wide daily use

**IN PROGRESS.**

The following Phase 2 milestones are already proven:

- Linux Mint `fprintd` can load the known-good MR !626 libfprint build through a systemd override;
- `fprintd-list` detects the sensor correctly;
- the required Validity data can be installed as real system files under `/usr/local/share/libfprint/validity/`;
- `fprintd-enroll` successfully completes a full right-index enrollment.

Still to prove:

- `fprintd-verify` correct-finger and wrong-finger behavior;
- `sudo` authentication;
- desktop login;
- lock-screen unlock;
- reboot persistence;
- suspend/resume reliability;
- final cleanup and rollback instructions.

Do not modify PAM until `fprintd-verify` has been proven first.

---

# Files preserved in this repository

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

These are the frozen known-good Validity files used by the successful setup.

---

# Phase 1 — Fresh-install procedure

## Step 1 — Confirm the hardware

```bash
lsusb | grep -i 06cb:00b7
```

Expected to contain:

```text
06cb:00b7 Synaptics, Inc. Fingerprint reader
```

If `06cb:00b7` is not present, stop. This guide is validated specifically for that reader.

---

## Step 2 — Install build dependencies

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

---

## Step 3 — Clone the exact known-good libfprint source

Known-good commit:

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

Verify:

```bash
git -C libfprint rev-parse HEAD
```

Expected exactly:

```text
0fd78560a245eebec1c93e71ee1f29b15ec1be67
```

---

## Step 4 — Create the build environment

```bash
python3 -m venv tools-venv
source tools-venv/bin/activate
pip install meson ninja
```

Known-good reference versions:

```text
Meson 1.12.0
Ninja 1.13.2
```

---

## Step 5 — Build only the Validity driver

```bash
meson setup build libfprint -Ddrivers=validity -Ddoc=false
ninja -C build
```

The successful build completed cleanly.

Do **not** run `ninja install`.

---

## Step 6 — Verify the preserved Validity data

From `FingerPrint_Sensor/`:

```bash
cd permanent-data/validity
sha256sum -c SHA256SUMS
cd ../..
```

All nine entries must report:

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

If any file reports `FAILED`, stop.

---

## Step 7 — Install the Validity data as real system files

This is important: do **not** use symlinks from `/usr/local/share/libfprint/validity/` back into your home directory for the final/system-wide setup.

`fprintd.service` uses:

```text
ProtectHome=true
```

so it cannot follow such symlinks into `/home/...`.

Install the device-specific files:

```bash
sudo mkdir -p /usr/local/share/libfprint/validity/06cb_00b7
sudo install -m 0644 \
  permanent-data/validity/06cb_00b7/init.bin \
  permanent-data/validity/06cb_00b7/db_write_enable.bin \
  /usr/local/share/libfprint/validity/06cb_00b7/
```

Install the shared files:

```bash
sudo install -m 0644 \
  permanent-data/validity/partition_sig_standard.bin \
  permanent-data/validity/partition_sig_0090.bin \
  permanent-data/validity/ca_pubkey.bin \
  permanent-data/validity/tls_password.bin \
  permanent-data/validity/gwk_sign.bin \
  permanent-data/validity/fw_pubkey_x.bin \
  permanent-data/validity/fw_pubkey_y.bin \
  /usr/local/share/libfprint/validity/
```

Do not add `reset.bin` or `init_clean_slate.bin`; they were not needed.

---

## Step 8 — Optional build-tree enrollment test

This proves the native driver before system integration.

```bash
source tools-venv/bin/activate
sudo env LD_LIBRARY_PATH="$PWD/build/libfprint" \
  ./build/examples/enroll
```

Known-good result includes:

```text
ENROLL_NUM_STATES completed successfully
Print for finger FP_FINGER_RIGHT_INDEX enrolled
```

---

## Step 9 — Optional build-tree verification test

Correct finger:

```bash
sudo env LD_LIBRARY_PATH="$PWD/build/libfprint" \
  ./build/examples/verify
```

Expected:

```text
MATCH!
```

Repeat with a different finger.

Expected:

```text
NO MATCH!
```

At this point Phase 1 is complete.

---

# Phase 2 — System-wide `fprintd` integration

The following steps are already proven on the real machine.

## Step 1 — Confirm how `fprintd` is installed

```bash
dpkg -L fprintd | grep -E '/fprintd$|systemd|dbus'
```

Known-good Mint installation uses:

```text
/usr/libexec/fprintd
/usr/lib/systemd/system/fprintd.service
```

---

## Step 2 — Confirm the daemon expects the same libfprint SONAME

```bash
ldd /usr/libexec/fprintd | grep -i fprint
```

The daemon expects:

```text
libfprint-2.so.2
```

Confirm the built library has the same SONAME:

```bash
readelf -d build/libfprint/libfprint-2.so.2.0.0 | grep SONAME
```

Expected:

```text
Library soname: [libfprint-2.so.2]
```

---

## Step 3 — Confirm the loader can redirect `fprintd` to the build

```bash
LD_LIBRARY_PATH="$PWD/build/libfprint" \
ldd /usr/libexec/fprintd | grep -i fprint
```

Expected `libfprint-2.so.2` to resolve to the build-tree library.

---

## Step 4 — Stage the known-good libfprint under `/usr/local`

```bash
sudo mkdir -p /usr/local/lib/fprintd-validity
sudo cp -a \
  build/libfprint/libfprint-2.so.2 \
  build/libfprint/libfprint-2.so.2.0.0 \
  /usr/local/lib/fprintd-validity/
```

This does **not** overwrite Mint's distro libfprint.

For a clean final state, root ownership is preferred:

```bash
sudo chown -R root:root /usr/local/lib/fprintd-validity
```

---

## Step 5 — Create a reversible systemd override

Do not edit `/usr/lib/systemd/system/fprintd.service` directly.

Create a drop-in:

```bash
sudo mkdir -p /etc/systemd/system/fprintd.service.d
printf '%s\n' \
'[Service]' \
'Environment=LD_LIBRARY_PATH=/usr/local/lib/fprintd-validity' | \
sudo tee /etc/systemd/system/fprintd.service.d/validity.conf
```

Reload and restart:

```bash
sudo systemctl daemon-reload
sudo systemctl restart fprintd
```

Verify the effective environment:

```bash
systemctl show fprintd -p Environment
```

Expected:

```text
Environment=LD_LIBRARY_PATH=/usr/local/lib/fprintd-validity
```

---

## Step 6 — Confirm `fprintd` sees the sensor

```bash
fprintd-list "$USER"
```

Known-good result:

```text
found 1 devices
Device at /net/reactivated/Fprint/Device/0
Using device /net/reactivated/Fprint/Device/0
User asif has no fingers enrolled for Validity VCSFW Fingerprint Sensor.
```

The important part is that `Validity VCSFW Fingerprint Sensor` is detected.

---

## Step 7 — Important sandbox note

If `fprintd-enroll` fails with:

```text
Required file init.bin not found for 06cb:00b7
```

check whether the files under `/usr/local/share/libfprint/validity/` are symlinks into `/home/...`.

Because `fprintd.service` contains:

```text
ProtectHome=true
```

those symlinks will not work.

Replace them with real files using the `sudo install -m 0644 ...` commands from Phase 1 Step 7.

---

## Step 8 — Enroll through `fprintd`

Restart the daemon first:

```bash
sudo systemctl restart fprintd
```

Then enroll the right index finger:

```bash
fprintd-enroll -f right-index-finger "$USER"
```

Known-good successful output:

```text
Using device /net/reactivated/Fprint/Device/0
Enrolling right-index-finger finger.
Enroll result: enroll-stage-passed
Enroll result: enroll-stage-passed
Enroll result: enroll-stage-passed
Enroll result: enroll-stage-passed
Enroll result: enroll-stage-passed
Enroll result: enroll-stage-passed
Enroll result: enroll-stage-passed
Enroll result: enroll-stage-passed
Enroll result: enroll-completed
```

This is the first proven full system-level enrollment through Linux Mint's normal `fprintd` service.

---

# Current Phase 2 checkpoint

At this point the following are proven:

```text
fprintd loads known-good MR !626 libfprint     PASS
fprintd sees 06cb:00b7                         PASS
Validity data accessible to sandboxed daemon  PASS
fprintd right-index enrollment                 PASS
```

Next required test before touching PAM:

```text
fprintd-verify correct finger
fprintd-verify wrong finger
```

Only after those succeed should `sudo`, login, and lock-screen authentication be enabled.

---

# Stable vs changing pieces

## Stable known-good anchors

```text
USB ID                  06cb:00b7
Sensor                   57K0 FM-3439-001
Sensor type              0x0d51
Working libfprint commit 0fd78560a245eebec1c93e71ee1f29b15ec1be67
Required device file     init.bin
Required DB file         db_write_enable.bin
Shared Validity files    7 files listed above
```

## Things that may change

- current upstream libfprint `master`;
- MR !626 branch state;
- Mint/Ubuntu package versions;
- Meson/Ninja versions;
- service hardening details in future `fprintd` releases;
- whether Mint eventually ships direct support for `06cb:00b7`.

If a future distro release supports the sensor natively, prefer the distro-native path and keep this guide as the known-good fallback.

---

# For AI assistants reading this repository

1. Read `README.md` first.
2. Treat Phase 1 as solved.
3. Treat the current Phase 2 checkpoint as: **`fprintd-enroll` works successfully.**
4. Do not restart reverse engineering unless new evidence shows a regression.
5. Do not regenerate the preserved Validity files unless they are missing or fail SHA-256 verification.
6. Do not replace Mint's system libfprint blindly; the proven method currently stages the library under `/usr/local/lib/fprintd-validity/` and uses a systemd override.
7. Do not enable PAM until `fprintd-verify` has been proven for both correct and incorrect fingers.
