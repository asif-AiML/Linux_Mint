# Fingerprint Reader on HP EliteBook 840 G6 — Native Linux Investigation Log

**Project:** Native Linux fingerprint support on Linux Mint  
**Machine:** HP EliteBook 840 G6  
**Sensor:** Synaptics `06cb:00b7` — Fingerprint reader [HP G6]  
**OS:** Linux Mint 22.3 (Zena), Ubuntu Noble base  
**Kernel during testing:** `7.0.0-30-generic`  
**Current target:** native libfprint MR !626 Validity driver  
**Current state:** **Native build-tree enrollment and verification both succeed.** The physical `06cb:00b7` / 57K0 / `0xd51` reader is now proven to open, calibrate, enroll a right-index fingerprint, match that enrolled finger, and reject a different finger. The next phase is clean fprintd/system integration for daily use.

---

## 1. Goal

Make the built-in fingerprint reader work natively under Linux Mint through the normal libfprint/fprintd/PAM stack and ultimately use it for:

- desktop login,
- lock-screen unlock,
- `sudo`,
- other appropriate PAM-backed authentication paths.

Success milestones:

1. libfprint recognizes and opens the sensor. **DONE**
2. Finger detection and capture work. **DONE**
3. Full multi-scan enrollment succeeds. **DONE**
4. Correct-finger verification succeeds. **DONE**
5. Wrong-finger verification rejects. **DONE**
6. fprintd integration works reliably. **NEXT**
7. PAM/login/sudo integration works reliably.
8. Suspend/resume behavior is stable.

---

## 2. Baseline

Installed fingerprint packages included:

- `fprintd`
- `libfprint-2-2`
- `libfprint-2-tod1`
- `libpam-fprintd`

The stock Mint/Noble stack returned:

```text
No devices available
```

USB enumeration showed:

```text
06cb:00b7 Synaptics, Inc. Fingerprint reader [HP G6]
```

The same physical reader works correctly under Windows.

---

## 3. Native libfprint MR !626

libfprint merge request **!626** contains a native Validity/Synaptics implementation with explicit support for this family.

Important source evidence includes:

- `VALIDITY_DEV_B7` for `06cb:00b7`,
- HP EliteBook 840 G6 references,
- firmware-extension handling for `06cb:00b7`,
- mapping to the 57K0 family and type `0x0d51`,
- special capture behavior for the HP G6/0xd51 family.

The branch is checked out locally as:

```text
mr-626
```

The experimental driver is still being tested from the build tree and has **not** been installed over the system libfprint.

No `ninja install` has been performed.

---

## 4. Build environment

Workspace:

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

MR !626 built completely:

```text
[120/120]
```

---

## 5. First runtime blockers

The first build-tree test selected the Validity driver but normal-user USB access failed:

```text
USB error on device 06cb:00b7 : Access denied
```

Temporary elevated testing removed that blocker without adding a permanent udev rule.

The next blocker was missing external Validity data:

```text
Device data files not found for 06cb:00b7.
Install the libfprint-validity-data package.
```

The driver searches paths including:

```text
/usr/local/share/libfprint/validity/06cb_00b7/
```

---

## 6. Exact hardware / firmware evidence

The exact Windows driver package for:

```text
USB\VID_06CB&PID_00B7
```

contains:

```text
6_07f_hp_cmit_mis_qm.xpfwext
```

which matches MR !626's firmware-extension mapping for `06cb:00b7`.

Native runtime reported:

```text
Firmware extension is loaded
```

Firmware tuple:

```text
Version: 6.7
Product: 48
Build Num: 164
Build Time: 1415491824
```

The driver identified the hardware directly as:

```text
Device: 57K0 FM-3439-001 (type=0x0d51)
Sensor type: 0x0d51, 120 bytes/line, 2x repeat
```

This confirms the machine contains the `0xd51` / 57K0 variant.

---

## 7. Validity data investigation

A published `libfprint-validity-data` package was downloaded and extracted locally instead of forcing an unsupported PPA onto Noble.

It contained data for:

```text
06cb_009a
138a_0090
138a_0097
138a_009d
```

but no `06cb_00b7` directory.

The upstream generator maps python-validity-style payloads as follows:

```text
init_hardcoded             -> init.bin
init_hardcoded_clean_slate -> init_clean_slate.bin
reset_blob                 -> reset.bin
db_write_enable            -> db_write_enable.bin
```

Generated files include the HMAC-SHA256 integrity trailer expected by the native driver.

---

## 8. Creating `06cb_00b7/init.bin`

A local helper was created:

```text
~/fingerprint-path1/generate_b7_init.py
```

It uses the established `init_hardcoded` payload from `blobs_9a.py`, appends the required HMAC trailer, and writes:

```text
output/06cb_00b7/init.bin
```

Result:

```text
Payload size: 581 bytes
HMAC size: 32 bytes
Total size: 613 bytes
```

The upstream verifier reported:

```text
OK   init.bin (581 bytes)
Verified: 1 OK, 0 FAILED
```

The file is exposed through a reversible symlink:

```text
/usr/local/share/libfprint/validity/06cb_00b7/init.bin
```

---

## 9. Common Validity data

After `init.bin` loaded successfully, runtime stopped at missing common data.

The required common files were already present in the extracted package:

```text
partition_sig_standard.bin
partition_sig_0090.bin
ca_pubkey.bin
tls_password.bin
gwk_sign.bin
fw_pubkey_x.bin
fw_pubkey_y.bin
```

These are exposed through reversible symlinks under:

```text
/usr/local/share/libfprint/validity/
```

---

## 10. Native open / TLS / calibration success

With the required data available, the reader progressed through the full native open path.

Runtime reported:

```text
TLS handshake completed successfully
TLS session established (secure_rx=1 secure_tx=1)
```

and:

```text
Sensor calibration complete
OPEN_NUM_STATES completed successfully
Validity sensor opened successfully
```

The reader then entered interactive enrollment mode, detected a real finger, and captured enrollment stage 0 successfully.

---

## 11. Enrollment blocker: missing `db_write_enable.bin`

The first enrollment attempt stopped after the first real capture.

The log reached:

```text
Enroll capture (stage 0): ... error=0x00000000
```

and then numeric enrollment state 21.

Inspection of `ValidityEnrollState` mapped state 21 to:

```text
ENROLL_DB_WRITE_ENABLE
```

The state calls:

```c
const guint8 *blob = validity_db_get_write_enable_blob (self, &blob_len);
vcsfw_tls_cmd_send (self, ssm, blob, blob_len, NULL);
```

`validity_data_get_bytes()` returns `NULL` with length `0` when the corresponding blob is absent.

That matched the observed failure path exactly and identified `db_write_enable.bin` as the concrete enrollment blocker.

---

## 12. Creating and verifying `06cb_00b7/db_write_enable.bin`

`src/blobs_9a.py` contains an established `db_write_enable` payload.

The upstream generator already produces:

```text
06cb_009a/db_write_enable.bin
```

with:

```text
3621 bytes payload
3653 bytes total including HMAC
```

The generated, HMAC-protected file was copied into:

```text
output/06cb_00b7/db_write_enable.bin
```

The verifier then confirmed both B7 files:

```text
init.bin              OK
db_write_enable.bin   OK
```

The write-enable blob is exposed through:

```text
/usr/local/share/libfprint/validity/06cb_00b7/db_write_enable.bin
```

No reset or clean-slate payload was added.

---

## 13. FULL NATIVE ENROLLMENT SUCCESS

After adding the verified `db_write_enable.bin`, a new build-tree enrollment run completed the full state machine.

The decisive lines were:

```text
ENROLL_NUM_STATES completed successfully
Device reported enroll completion (... error: none)
Print for finger FP_FINGER_RIGHT_INDEX enrolled
Completing action FPI_DEVICE_ACTION_ENROLL in idle!
```

The device then closed normally.

The example also created its local print-reference file:

```text
~/fingerprint-path1/test-storage.variant
```

with the expected persisted enrollment reference.

This proves the full native right-index enrollment path works on the physical reader.

---

## 14. FULL NATIVE VERIFICATION SUCCESS

Two build-tree verification tests were then performed.

### Correct finger

Using the enrolled right index finger produced:

```text
Match report: device Validity VCSFW Fingerprint Sensor matched finger right index successfully
MATCH!
```

### Wrong finger

Using a different finger produced:

```text
Match report: Finger not matched
NO MATCH!
```

This is the strongest functional milestone so far: the native Validity driver can not only capture and enroll a fingerprint, but also distinguish the enrolled right-index fingerprint from a non-enrolled finger correctly.

---

## 15. What is proven now

### Proven on this machine

- Physical reader is `06cb:00b7`.
- Stock Mint/Noble libfprint does not expose it normally.
- MR !626 builds completely (`120/120`).
- Native Validity driver recognizes the reader.
- Firmware reads successfully.
- Firmware extension is already loaded.
- Exact hardware identifies as `57K0 FM-3439-001`, type `0x0d51`.
- Reused 9a-family initialization data is accepted.
- `06cb_00b7/init.bin` passes HMAC verification.
- Common Validity data are accepted.
- Existing TLS pairing state is valid.
- TLS handshake succeeds.
- Sensor calibration succeeds.
- Device opens successfully.
- Real finger detection and capture work.
- `db_write_enable.bin` was identified and fixed as the enrollment blocker.
- Full right-index enrollment succeeds.
- Local example print reference is created.
- **Correct right-index verification returns MATCH.**
- **Different-finger verification returns NO MATCH.**

### Still to prove

- Clean fprintd integration using the native driver.
- Clean system installation/integration strategy for the experimental driver and required data.
- PAM/sudo/login/lock-screen integration.
- Suspend/resume reliability.
- Long-term daily-use stability.

---

## 16. Current system changes

Most experimental work remains under:

```text
~/fingerprint-path1
```

Temporary/reversible filesystem exposure under `/usr/local` includes:

```text
/usr/local/share/libfprint/validity/06cb_00b7/init.bin
/usr/local/share/libfprint/validity/06cb_00b7/db_write_enable.bin
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

No `ninja install` has been performed.

No PAM configuration has been changed.

No permanent udev rule has been added.

Build-tree runtime testing still uses temporary elevation for USB access.

---

## 17. Immediate next milestone

The build-tree proof phase is complete.

The next phase is **clean system integration**:

1. determine the safest way for the installed `fprintd` service to use the MR !626 libfprint build without blindly overwriting the distro copy;
2. enroll/verify through `fprintd` rather than the standalone examples;
3. only then enable PAM integration for `sudo`, login, and lock-screen authentication;
4. keep password authentication available as fallback throughout testing;
5. test suspend/resume and repeated daily-use cycles before calling the setup stable.

---

## 18. Current project state in one sentence

> **Native Linux operation of the HP EliteBook 840 G6 `06cb:00b7` fingerprint reader is now functionally proven end-to-end at the libfprint build-tree level: MR !626 opens and identifies the 57K0/`0xd51` sensor, completes TLS and calibration, enrolls the right index finger, matches that finger successfully, and rejects a different finger; the remaining work is safe fprintd/PAM integration for daily use.**