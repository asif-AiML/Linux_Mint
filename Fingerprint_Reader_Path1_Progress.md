# Fingerprint Reader on HP EliteBook 840 G6 — Native Linux Investigation Log

**Project:** Native Linux fingerprint support on Linux Mint  
**Machine:** HP EliteBook 840 G6  
**Sensor:** Synaptics `06cb:00b7` — Fingerprint reader [HP G6]  
**OS:** Linux Mint 22.3 (Zena), Ubuntu Noble base  
**Kernel during testing:** `7.0.0-30-generic`  
**Current target:** native libfprint MR !626 Validity driver  
**Current state:** **Native build-tree enrollment now succeeds completely.** MR !626 recognizes, opens, identifies, calibrates, captures from, and enrolls the physical `06cb:00b7` / 57K0 / `0xd51` reader successfully when supplied with the required Validity data. The missing enrollment blocker was the per-device `db_write_enable.bin` payload. Correct-finger verification is the immediate next milestone before fprintd/PAM integration.

---

## 1. Goal

The built-in fingerprint reader works correctly under Windows but is not exposed by the stable fingerprint stack shipped with Linux Mint.

The objective is to make the reader work natively through libfprint/fprintd and eventually integrate it safely with normal daily authentication such as:

- desktop login,
- lock-screen unlock,
- `sudo`,
- other PAM-backed authentication paths where appropriate.

Success milestones:

1. libfprint recognizes and opens the sensor. **DONE**
2. Finger detection and real capture work. **DONE**
3. Full native multi-scan enrollment succeeds. **DONE**
4. Correct-finger verification succeeds and wrong-finger verification rejects. **NEXT**
5. Normal non-root device access works.
6. fprintd integration works reliably.
7. PAM/login/sudo integration works reliably.
8. Suspend/resume behavior is stable.

---

## 2. Project phases

The work was initially described as two paths:

- **Path 1:** practical reuse/integration of existing native support.
- **Path 2:** deeper protocol/driver engineering if existing support is incomplete.

This distinction is now only a complexity marker, not a hard project boundary. Deeper source work, protocol analysis, USB tracing, or driver changes are treated as the next engineering phase of the same fingerprint project.

The runtime target remains native libfprint. `python-validity` is used only as an upstream reference/evidence source where its recent work covers the same hardware family.

---

## 3. Baseline

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

## 4. Native libfprint MR !626

libfprint merge request **!626** contains a native Validity/Synaptics implementation with explicit support for this family.

Important source evidence includes:

- `VALIDITY_DEV_B7` for `06cb:00b7`,
- HP EliteBook 840 G6 references,
- firmware-extension handling for `06cb:00b7`,
- sensor mapping to the 57K0 family and type `0x0d51`,
- special capture behavior for the HP G6/0xd51 family.

The branch was fetched as:

```text
mr-626
```

The experimental driver is still being tested from the build tree and has **not** been installed over the system libfprint.

---

## 5. Build environment

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

No `ninja install` has been performed.

---

## 6. First runtime blockers

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

Device-specific files include:

```text
init.bin
init_clean_slate.bin
reset.bin
db_write_enable.bin
```

---

## 7. Exact hardware / firmware evidence

The exact Windows driver package for:

```text
USB\VID_06CB&PID_00B7
```

contains:

```text
6_07f_hp_cmit_mis_qm.xpfwext
```

which matches MR !626's firmware-extension mapping for `06cb:00b7`.

Native runtime later reported:

```text
Firmware extension is loaded
```

The firmware tuple was read successfully:

```text
Version: 6.7
Product: 48
Build Num: 164
Build Time: 1415491824
```

The driver then identified the hardware directly as:

```text
Device: 57K0 FM-3439-001 (type=0x0d51)
Sensor type: 0x0d51, 120 bytes/line, 2x repeat
```

This confirms the machine contains the `0xd51` / 57K0 variant.

---

## 8. Validity data investigation

A published `libfprint-validity-data` package was downloaded and extracted locally instead of forcing an unsupported PPA onto Noble.

It contained device directories for:

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

Generated `.bin` files include a 32-byte HMAC-SHA256 integrity trailer expected by the native driver.

---

## 9. Creating `06cb_00b7/init.bin`

A local helper was created:

```text
~/fingerprint-path1/generate_b7_init.py
```

It uses the established `init_hardcoded` payload from `blobs_9a.py`, appends the expected HMAC trailer, and writes:

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

The verified file is exposed through a reversible symlink:

```text
/usr/local/share/libfprint/validity/06cb_00b7/init.bin
```

---

## 10. Common Validity data

After `init.bin` loaded successfully, runtime stopped at a missing common file:

```text
Common data file 'partition_sig_standard.bin' not found.
```

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

## 11. Native open / TLS / calibration success

With `init.bin` and common data available, the build-tree driver progressed through the full open path.

The reader accepted the initialization data and existing pairing state. Runtime reported:

```text
TLS handshake completed successfully
TLS session established (secure_rx=1 secure_tx=1)
```

The exact sensor was identified as:

```text
Device: 57K0 FM-3439-001 (type=0x0d51)
Sensor type: 0x0d51, 120 bytes/line, 2x repeat
```

Three calibration iterations completed and the driver reported:

```text
Sensor calibration complete
OPEN_NUM_STATES completed successfully
Validity sensor opened successfully
```

The reader then correctly entered interactive enrollment mode, detected a real finger, and captured enrollment stage 0 successfully.

---

## 12. Enrollment blocker discovered: missing `db_write_enable.bin`

The first enrollment attempt appeared to stop immediately after the first scan.

The log reached:

```text
Enroll capture (stage 0): ... error=0x00000000
```

and later entered numeric enrollment state 21.

Inspection of `ValidityEnrollState` mapped state 21 to:

```text
ENROLL_DB_WRITE_ENABLE
```

The relevant state calls:

```c
const guint8 *blob = validity_db_get_write_enable_blob (self, &blob_len);
vcsfw_tls_cmd_send (self, ssm, blob, blob_len, NULL);
```

`validity_db_get_write_enable_blob()` directly retrieves `VALIDITY_DATA_DB_WRITE_ENABLE` from the loaded data store.

Inspection of `validity_data_get_bytes()` confirmed that when the blob is absent it returns:

```text
NULL
```

with length:

```text
0
```

This matched the runtime behavior exactly: the enrollment state machine reached the write-enable stage and then could not proceed normally.

The previously absent `db_write_enable.bin` therefore changed from an apparently optional startup file into the concrete enrollment blocker.

---

## 13. Creating and verifying `06cb_00b7/db_write_enable.bin`

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

Because the B7 investigation already established reuse of the corresponding 9a-family data for this `0xd51` path, the generated and HMAC-protected `06cb_009a/db_write_enable.bin` was copied into:

```text
output/06cb_00b7/db_write_enable.bin
```

The package verifier then confirmed both B7 files as valid:

```text
init.bin              OK
db_write_enable.bin   OK
```

The write-enable blob is now exposed through the reversible symlink:

```text
/usr/local/share/libfprint/validity/06cb_00b7/db_write_enable.bin
```

No reset or clean-slate payload was added.

---

## 14. MAJOR MILESTONE: FULL NATIVE ENROLLMENT SUCCESS

A new build-tree enrollment run (`enroll-runtime-4.txt`) was started after exposing the verified `db_write_enable.bin`.

This time the interaction continued across repeated finger placements instead of terminating after stage 0. The user physically touched the sensor seven times during the successful run.

The decisive final runtime lines were:

```text
ENROLL_NUM_STATES completed successfully
Device reported enroll completion (... error: none)
Print for finger FP_FINGER_RIGHT_INDEX enrolled
Completing action FPI_DEVICE_ACTION_ENROLL in idle!
```

This is definitive evidence that the native libfprint enrollment state machine completed and libfprint accepted the right-index fingerprint as enrolled.

The device then closed normally:

```text
Device reported close completion (error: none)
```

Therefore, **full native build-tree enrollment is now proven on the physical HP EliteBook 840 G6 reader.**

### Local example-storage warning

Immediately after successful enrollment, the example attempted to save a local print reference and logged:

```text
Device has storage, saving a print reference locally
Error loading storage, assuming it is empty
```

This warning occurs after device enrollment has already succeeded. It refers to the example program's local `test-storage.variant` persistence layer, not to failure of sensor enrollment itself.

The next test is to confirm that `test-storage.variant` was created and then perform correct-finger and wrong-finger verification.

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
- Reused 9a-family `init_hardcoded` data is accepted.
- Generated `06cb_00b7/init.bin` passes HMAC verification.
- Common Validity data are accepted.
- Existing TLS pairing state is valid.
- TLS handshake succeeds.
- Sensor calibration succeeds.
- Device opens successfully.
- Real finger detection works.
- Real fingerprint capture works.
- `db_write_enable.bin` was identified as the blocker after the first capture.
- Reused 9a-family write-enable data passes HMAC verification for the B7 test directory.
- **Full native build-tree right-index enrollment succeeds.**

### Still to prove

- Local example storage file creation.
- Correct-finger verification.
- Wrong-finger rejection.
- Normal non-root device access through an appropriate udev rule.
- Reliable fprintd integration using the native driver.
- Clean system installation/integration strategy for the experimental driver and data.
- PAM/sudo/login/lock-screen integration.
- Suspend/resume reliability.

---

## 16. Current system changes

Most experimental work remains under:

```text
~/fingerprint-path1
```

Temporary/reversible filesystem exposure under `/usr/local` now includes:

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

The next gate is build-tree verification:

1. confirm the local `test-storage.variant` file exists;
2. verify the enrolled right index finger produces a match;
3. deliberately test a different finger and confirm it is rejected.

Only after both sides of verification are proven should normal-user USB access, fprintd integration, and finally PAM/login/sudo integration begin.

---

## 18. Current project state in one sentence

> **Native Linux operation of the HP EliteBook 840 G6 `06cb:00b7` fingerprint reader has now crossed the full enrollment threshold: libfprint MR !626 opens and identifies the 57K0/`0xd51` sensor, completes TLS and calibration, captures repeated real scans, and successfully completes right-index enrollment after adding the required `db_write_enable.bin`; verification is the next milestone before daily-use system integration.**