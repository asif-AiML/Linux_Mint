# Fingerprint Reader on HP EliteBook 840 G6 — Native Linux Investigation Log

**Project:** Native Linux fingerprint support on Linux Mint  
**Machine:** HP EliteBook 840 G6  
**Sensor:** Synaptics `06cb:00b7` — Fingerprint reader [HP G6]  
**OS:** Linux Mint 22.3 (Zena), Ubuntu Noble base  
**Kernel during testing:** `7.0.0-30-generic`  
**Current target:** native libfprint MR !626 Validity driver  
**Current state:** MR !626 now recognizes, opens, identifies, calibrates, and captures from the physical `06cb:00b7` reader successfully when supplied with the required Validity data. The first real enrollment capture (`stage 0`) succeeds, but a full 8-scan enrollment has **not yet been proven**. Verification and fprintd/PAM integration therefore remain blocked until the enrollment state-machine behavior is understood.

---

## 1. Goal

The built-in fingerprint reader works correctly under Windows but is not exposed by the stable fingerprint stack shipped with Linux Mint.

The objective is to make the reader work natively through libfprint/fprintd and eventually integrate it safely with desktop/login authentication.

Success milestones:

1. libfprint recognizes and opens the sensor. **DONE**
2. Finger detection and real fingerprint capture work. **DONE**
3. Full multi-scan enrollment succeeds. **CURRENT BLOCKER**
4. Verification distinguishes the correct finger from an incorrect finger.
5. fprintd integration works reliably.
6. PAM/login/sudo integration works reliably.

---

## 2. Project phases

The work was initially described as two paths:

- **Path 1:** practical reuse/integration of existing native support.
- **Path 2:** deeper protocol/driver engineering if existing support is incomplete.

This is now treated only as a complexity distinction, not a hard project boundary. If deeper source work, protocol analysis, USB tracing, or driver changes become necessary, they are simply the next engineering phase of the same project.

The runtime target remains native libfprint. `python-validity` is used only as a reference/evidence source where its recent work covers the same hardware family.

---

## 3. Baseline

Stock Mint fingerprint packages were already installed:

- `fprintd`
- `libfprint-2-2`
- `libfprint-2-tod1`
- `libpam-fprintd`

The stock device test returned:

```text
No devices available
```

USB enumeration showed:

```text
06cb:00b7 Synaptics, Inc. Fingerprint reader [HP G6]
```

The reader is vendor-specific USB hardware and works correctly under Windows.

---

## 4. Native libfprint MR !626

libfprint merge request **!626** contains a native Validity/Synaptics implementation with explicit support references for this sensor.

Important source evidence includes:

- `VALIDITY_DEV_B7` for `06cb:00b7`,
- HAL entry for PID `0x00b7`,
- HP EliteBook 840 G6 references,
- firmware-extension handling for `06cb:00b7`,
- sensor mapping to the 57K0 family and type `0x0d51`,
- special capture behavior for the HP G6/0xd51 family.

The branch was fetched as:

```text
mr-626
```

The experimental driver has not been installed over the system libfprint; tests are still being performed directly from the build tree.

---

## 5. Build environment and successful build

Main workspace:

```text
~/fingerprint-path1
```

Important paths:

```text
~/fingerprint-path1/libfprint
~/fingerprint-path1/tools-venv
~/fingerprint-path1/validity-data
~/fingerprint-path1/windows-driver
```

APT development packages added during build troubleshooting:

- `libgusb-dev`
- `libusb-1.0-0-dev`
- `libjson-glib-dev`
- `libssl-dev`
- `gobject-introspection`

After dependency issues were resolved, MR !626 built completely:

```text
[120/120]
```

---

## 6. First runtime blockers

The first build-tree enrollment attempt selected the Validity driver but failed because the USB device could not be opened by the normal user:

```text
USB error on device 06cb:00b7 : Access denied
```

A temporary elevated test removed that blocker without adding a permanent udev rule.

The next failure was:

```text
Device data files not found for 06cb:00b7.
Install the libfprint-validity-data package.
```

The driver expected a device directory such as:

```text
/usr/local/share/libfprint/validity/06cb_00b7/
```

with mandatory `init.bin` and optional files including:

```text
init_clean_slate.bin
reset.bin
db_write_enable.bin
```

---

## 7. Windows driver and firmware investigation

The exact Windows driver package for:

```text
USB\VID_06CB&PID_00B7
```

was obtained and extracted.

It contains:

```text
6_07f_hp_cmit_mis_qm.xpfwext
```

which exactly matches MR !626's firmware-extension mapping for `06cb:00b7`.

Later runtime logs showed:

```text
Firmware extension is loaded
```

so firmware extension loading was not the remaining blocker on this machine.

---

## 8. libfprint-validity-data investigation

A published `libfprint-validity-data` package was downloaded and extracted locally instead of forcing an unsupported PPA onto Noble.

It contained data for:

```text
06cb_009a
138a_0090
138a_0097
138a_009d
```

but no:

```text
06cb_00b7
```

The source package revealed `generate_data.py`, which converts existing python-validity-style payload definitions into libfprint `.bin` files by appending a 32-byte HMAC-SHA256 integrity trailer.

The relevant mapping is:

```text
init_hardcoded             -> init.bin
init_hardcoded_clean_slate -> init_clean_slate.bin
reset_blob                 -> reset.bin
db_write_enable            -> db_write_enable.bin
```

The generator does not synthesize protocol payloads from VID/PID; it packages already-known payloads.

---

## 9. Why python-validity appeared again

The runtime solution did **not** switch back to python-validity.

Recent `python-validity` PR #256 became useful because it specifically covers sensor type `0xd51` and the exact USB ID `06cb:00b7`. It provided evidence that established normal initialization data can be reused for this family and that earlier failures were caused by deeper capture/protocol behavior rather than necessarily requiring a unique B7 initialization blob.

That evidence justified a controlled native-libfprint experiment using only the normal initialization payload while deliberately avoiding reset/clean-slate payloads.

---

## 10. Device identity confirmed

A debug build-tree run showed the firmware tuple:

```text
Version: 6.7
Product: 48
Build Num: 164
Build Time: 1415491824
```

The later successful open path identified the hardware directly:

```text
Device: 57K0 FM-3439-001 (type=0x0d51)
Sensor type: 0x0d51, 120 bytes/line, 2x repeat
```

This confirms that this HP EliteBook 840 G6 contains the `0xd51` / 57K0 variant, not the alternate `0x969` silicon that has also appeared under USB PID `06cb:00b7` on some HP systems.

---

## 11. Creating the missing `06cb_00b7/init.bin`

A small local helper was created in VS Code:

```text
~/fingerprint-path1/generate_b7_init.py
```

It reads only `init_hardcoded` from the existing `blobs_9a.py`, appends the same HMAC-SHA256 integrity trailer expected by MR !626, and writes:

```text
output/06cb_00b7/init.bin
```

Result:

```text
Payload size: 581 bytes
HMAC size:    32 bytes
Total size:   613 bytes
```

The generated file was verified using the package's own verifier:

```text
OK   init.bin (581 bytes)
Verified: 1 OK, 0 FAILED
```

Only `init.bin` was generated. No `reset.bin`, `init_clean_slate.bin`, or `db_write_enable.bin` was synthesized for the B7 device.

The verified file was exposed through a reversible symlink under:

```text
/usr/local/share/libfprint/validity/06cb_00b7/init.bin
```

---

## 12. Common Validity data blocker

The next native run successfully loaded the new device-specific file:

```text
Loaded data file: /usr/local/share/libfprint/validity/06cb_00b7/init.bin (581 bytes)
```

and then stopped because common data were missing:

```text
Common data file 'partition_sig_standard.bin' not found.
```

The already-extracted package contained the required common files:

```text
partition_sig_standard.bin
partition_sig_0090.bin
ca_pubkey.bin
tls_password.bin
gwk_sign.bin
fw_pubkey_x.bin
fw_pubkey_y.bin
```

These were exposed through reversible symlinks under:

```text
/usr/local/share/libfprint/validity/
```

No experimental libfprint installation was performed.

---

## 13. Major milestone: native device open + real capture SUCCESS

After the verified `06cb_00b7/init.bin` and common Validity files were available, the third build-tree enrollment run progressed through the full native driver initialization path.

### External data loaded successfully

The driver loaded:

```text
init.bin (581 bytes)
partition_sig_standard.bin
partition_sig_0090.bin
ca_pubkey.bin
tls_password.bin
gwk_sign.bin
fw_pubkey_x.bin
fw_pubkey_y.bin
```

and reported:

```text
Loaded external data files for 06cb:00b7
Sending init_hardcoded (581 bytes)
```

The optional B7 files remained absent without preventing startup:

```text
init_clean_slate.bin
reset.bin
db_write_enable.bin
```

### Pairing/TLS state succeeded

The reader's flash was inspected and the existing TLS keys were accepted:

```text
TLS keys verified on flash — pairing not needed
```

The driver successfully loaded the TLS private key, certificate, and ECDH public key and completed the TLS handshake:

```text
TLS handshake completed successfully
TLS session established (secure_rx=1 secure_tx=1)
```

### Exact physical sensor identification succeeded

The native driver identified the sensor as:

```text
Device: 57K0 FM-3439-001 (type=0x0d51)
Sensor type: 0x0d51, 120 bytes/line, 2x repeat
```

### Calibration succeeded

The driver performed three sensor-calibration iterations, reading calibration data from endpoint `0x82`, and finished with:

```text
Sensor calibration complete
OPEN_NUM_STATES completed successfully
Validity sensor opened successfully
```

This proves the reader can complete the full native open state machine under Linux.

### Enrollment became genuinely interactive

The program printed:

```text
Opened device.
It's now time to enroll your finger.
You will need to successfully scan your right index finger 8 times to complete the process.
Scan your finger now.
```

The pause at this point was correct behavior: the process was waiting for a physical finger.

When the right index finger was placed on the sensor, the driver reported:

```text
Finger detected on sensor
```

and libfprint's finger state changed from:

```text
FP_FINGER_STATUS_NEEDED
```

to:

```text
FP_FINGER_STATUS_PRESENT
```

The log then showed real capture interrupts and a first enrollment capture:

```text
Enroll capture (stage 0): ... error=0x00000000
```

This is a major functional success: the native driver is not merely recognizing the hardware; it is operating the sensor and capturing a real fingerprint.

### Important correction: full enrollment was NOT completed

The first interpretation of this run was too optimistic. The example explicitly requires **8 successful scans**, but the captured log proves only the first enrollment sample (`stage 0`). There is no evidence of later stages completing, no final successful enrollment callback, and no locally persisted `test-storage.variant` fingerprint record.

A later verification attempt therefore failed immediately with:

```text
Error loading storage, assuming it is empty
Failed to load fingerprint data
Did you remember to enroll your right index finger first?
```

Inspection of the example source confirmed that a completed enrollment should call `print_data_save(...)`, which writes the local test storage file. Because that file was never created, the current evidence is consistent with enrollment stopping after the first capture rather than completing all eight scans.

The present investigation is therefore focused on the state-machine behavior immediately after `Enroll capture (stage 0)`.

---

## 14. What is proven now

### Proven on this machine

- Physical reader is `06cb:00b7`.
- Stock Mint/Noble libfprint does not expose it normally.
- MR !626 explicitly supports the family and builds completely (`120/120`).
- The build-tree Validity driver recognizes the reader.
- Firmware is read successfully as version 6.7 / product 48 / build 164 / timestamp 1415491824.
- Firmware extension is already loaded.
- The hardware identifies directly as `57K0 FM-3439-001`, type `0x0d51`.
- A normal `init_hardcoded` payload reused from the established blob family is accepted by the device.
- The generated `06cb_00b7/init.bin` passes the data package's HMAC verifier.
- The common Validity files are accepted.
- Existing TLS flash keys are valid; re-pairing is not required.
- TLS handshake succeeds.
- Sensor calibration succeeds.
- The native driver opens the reader successfully.
- The reader detects a real finger.
- A real fingerprint capture succeeds at enrollment `stage 0`.

### Not yet proven

- Full 8-scan enrollment completion.
- Creation of a persistent enrolled-print record.
- Verification of the correct finger.
- Rejection of a wrong finger.
- Normal non-root device access through an appropriate udev rule.
- Reliable fprintd integration using the native driver.
- System installation strategy for the experimental/native driver and required data.
- PAM/sudo/login/lock-screen integration.
- Suspend/resume reliability.

---

## 15. Current system changes

Most experimental work remains under:

```text
~/fingerprint-path1
```

APT development packages installed:

- `libgusb-dev`
- `libusb-1.0-0-dev`
- `libjson-glib-dev`
- `libssl-dev`
- `gobject-introspection`

Temporary/reversible filesystem exposure under `/usr/local`:

```text
/usr/local/share/libfprint/validity/06cb_00b7/init.bin
/usr/local/share/libfprint/validity/partition_sig_standard.bin
/usr/local/share/libfprint/validity/partition_sig_0090.bin
/usr/local/share/libfprint/validity/ca_pubkey.bin
/usr/local/share/libfprint/validity/tls_password.bin
/usr/local/share/libfprint/validity/gwk_sign.bin
/usr/local/share/libfprint/validity/fw_pubkey_x.bin
/usr/local/share/libfprint/validity/fw_pubkey_y.bin
```

These are symlinks to files under the experimental workspace.

The experimental MR !626 libfprint driver has **not** been installed over the system libfprint.

No PAM configuration has been changed.

No permanent udev rule has been added.

Build-tree runtime testing still uses temporary elevation for USB access.

---

## 16. Immediate next milestone

The immediate task is to inspect what happens directly after the first successful enrollment capture.

The next diagnostic target is the tail of:

```text
~/fingerprint-path1/enroll-runtime-3.txt
```

The goal is to determine whether the driver:

- interprets a post-capture sensor status incorrectly,
- terminates enrollment after the first sample,
- fails to transition back to "finger needed" for scan 2,
- or encounters another silent state-machine condition.

Only after full multi-scan enrollment is proven should verification and then fprintd/PAM integration proceed.

---

## 17. Current project state in one sentence

> **Native Linux operation of the HP EliteBook 840 G6 `06cb:00b7` fingerprint reader has crossed a major functional threshold: libfprint MR !626 now opens and identifies the reader as a 57K0/`0xd51` sensor, completes TLS and calibration, detects a real finger, and captures the first enrollment sample successfully; the remaining blocker is completing the full 8-scan enrollment sequence before verification and daily-use integration can begin.**