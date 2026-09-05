# Fingerprint Reader on HP EliteBook 840 G6 — Path 1 Progress Log

**Project:** Native Linux fingerprint support on Linux Mint  
**Machine:** HP EliteBook 840 G6  
**Sensor:** Synaptics `06cb:00b7` — Fingerprint reader [HP G6]  
**OS:** Linux Mint 22.3 (Zena), Ubuntu Noble base  
**Kernel during testing:** `7.0.0-30-generic`  
**Status:** Native MR !626 driver builds and recognizes the sensor. USB access works with temporary elevation. Current runtime blocker is still the missing `06cb_00b7/init.bin`, but the Windows driver and the source of `libfprint-validity-data` have now been inspected and the problem is much more narrowly defined.

---

## 1. Why this work started

The fingerprint reader in the HP EliteBook 840 G6 works correctly under Windows, but Linux Mint did not expose it through the normal fingerprint stack.

The system already had:

- `fprintd`
- `libfprint-2-2`
- `libfprint-2-tod1`
- `libpam-fprintd`

The normal test returned:

```text
No devices available
```

The USB device was confirmed as:

```text
06cb:00b7 Synaptics, Inc. Fingerprint reader [HP G6]
```

The reader is vendor-specific USB hardware with bulk and interrupt endpoints. There was no evidence of missing or disabled hardware.

---

## 2. Two-path strategy

### Path 1 — practical native attempt

Goal: make the existing reader work using an existing native Linux/libfprint implementation without developing a new fingerprint driver from scratch.

Success criteria:

1. Linux enumerates the sensor through a real libfprint driver.
2. The sensor opens successfully.
3. Fingerprint enrollment succeeds.
4. Fingerprint verification succeeds.

Path 1 may include building an existing development branch, normal build dependencies, using legitimate firmware/device-data files, and inspecting the matching Windows package.

Path 1 should stop if success requires substantial USB tracing, protocol reverse engineering, or implementation of new hardware logic.

### Path 2 — future open-source driver work

If Path 1 reaches that boundary, the work should become a separate driver-development project involving protocol analysis, USB capture, quirks, source changes, tests, and potentially upstream contribution.

Path 2 has **not** started.

---

## 3. python-validity route considered and rejected

An older route for some Validity/Synaptics sensors is `python-validity`.

Historical reports involving the HP EliteBook 840 G6 and `06cb:00b7` indicated that the older python-validity stack did not match/support this sensor correctly, so it was not selected as the main solution.

The current route is different:

```text
libfprint MR !626 native Validity driver
        ↓
      fprintd
        ↓
Linux enrollment / verification
```

The current work is therefore **not python-validity**, although later investigation shows that MR !626's external data package was generated from selected python-validity data definitions.

---

## 4. Discovery of libfprint MR !626

The key breakthrough was finding libfprint merge request **!626**, which contains a native Validity/Synaptics driver and explicit support references for:

```text
06cb:00b7
```

Relevant files include:

- `libfprint/drivers/validity/validity.h`
- `libfprint/drivers/validity/validity_fwext.c`
- `libfprint/drivers/validity/validity_hal.c`
- `libfprint/drivers/validity/validity_sensor.c`

Important source evidence includes:

- `VALIDITY_DEV_B7` for `06cb:00b7`,
- a HAL entry using PID `0x00b7`,
- HP EliteBook 840 G6 comments,
- a sensor-family entry describing the HP G6 series as a `57K0` family device,
- sensor ID `0x0d51`,
- firmware-extension handling explicitly including `06cb:00b7`.

This was stronger than the stable libfprint tree, where `00b7` appeared only in generic hardware metadata rather than a usable driver registration.

---

## 5. Isolated workspace

Main workspace:

```text
~/fingerprint-path1
```

Important subdirectories:

```text
~/fingerprint-path1/libfprint
~/fingerprint-path1/tools-venv
~/fingerprint-path1/validity-data
~/fingerprint-path1/windows-driver
```

MR !626 was fetched into local branch:

```text
mr-626
```

Meson and Ninja were initially kept inside `tools-venv`.

The general rule remains: keep experimental artifacts under `~/fingerprint-path1` wherever practical and avoid installing the experimental driver system-wide until build-tree enrollment and verification are proven.

---

## 6. Build dependency history

The early failures were build-environment failures, not driver failures.

### GUsb / libusb / json-glib

Locally extracted development packages produced fragile pkg-config paths pointing at `/usr/include/...` while headers were elsewhere under the project tree. This caused missing-header failures such as:

```text
fatal error: gusb.h: No such file or directory
```

A controlled exception to local-only dependencies was made and these APT development packages were installed:

- `libgusb-dev`
- `libusb-1.0-0-dev`
- `libjson-glib-dev`

### OpenSSL

Compilation then reached the Validity sources and failed on:

```text
openssl/evp.h: No such file or directory
```

`libssl-dev` resolved this.

### GObject Introspection

A later build failure occurred while generating `FPrint-2.0.gir` because a locally extracted wrapper expected:

```text
/usr/bin/g-ir-scanner
```

Installing `gobject-introspection` provided the required executable and helper.

---

## 7. Major build success

After a clean Meson setup and the required development packages, Ninja completed:

```text
[120/120]
```

The build successfully compiled and linked the native Validity implementation, including protocol, sensor, HAL, firmware-extension, TLS, pairing, enrollment, verification, capture, and database code.

The experimental driver itself has **not** been installed over the system libfprint.

---

## 8. First build-tree runtime test

The build-tree enrollment example was run directly against the newly built libfprint.

It reached the normal finger-selection menu. The first hardware failure was USB permissions:

```text
USB error on device 06cb:00b7 : Access denied
```

The debug output identified:

```text
libfprint-validity-DEBUG
```

for `06cb:00b7`.

This proved that MR !626 recognized the physical device and selected the native Validity driver.

A one-off elevated test was then used instead of creating a permanent udev rule. That removed the USB access blocker.

---

## 9. Current runtime blocker: missing device data

With USB access available, the driver progressed further into its open state machine and failed with:

```text
Device data files not found for 06cb:00b7.
Install the libfprint-validity-data package.
```

The driver searches locations including:

```text
/usr/share/libfprint/validity/
/usr/local/share/libfprint/validity/
```

The per-device directory for this sensor is:

```text
06cb_00b7/
```

Known per-device filenames are:

```text
init.bin
init_clean_slate.bin
reset.bin
db_write_enable.bin
```

`init.bin` is mandatory; the other per-device blobs are optional in the driver's loading logic.

Common package data includes files such as:

```text
partition_sig_standard.bin
partition_sig_0090.bin
ca_pubkey.bin
tls_password.bin
gwk_sign.bin
fw_pubkey_x.bin
fw_pubkey_y.bin
```

The `.bin` data is protected by an HMAC-SHA256 integrity trailer. This is an integrity mechanism, not a secret authentication mechanism, but it means the driver expects packaged data in a specific format.

---

## 10. Published `libfprint-validity-data` package

The package was found in the `m-jedrasik/libfprint-validity` PPA, but the PPA does not support Noble, so it was **not** added forcibly to the system.

The Resolute package was downloaded and extracted locally instead:

```text
libfprint-validity-data
Version: 0.1.0-1ppa2~resolute1
Architecture: all
```

It contains per-device data for:

```text
06cb_009a
138a_0090
138a_0097
138a_009d
```

but **not**:

```text
06cb_00b7
```

Therefore simply installing the available package would not solve the HP G6 reader's missing `init.bin`.

---

## 11. Matching Windows driver package investigation

The exact Windows package for the same hardware was obtained from the Microsoft Update Catalog and extracted locally under:

```text
~/fingerprint-path1/windows-driver/extracted
```

The package contains:

```text
6_07f_hp_cmit_mis_qm.xpfwext
IPTSecureFPUiWin32.dll
IPTSecureFPUix64.dll
IPTSecureFPWin32.dll
IPTSecureFPx64.dll
synaAdvAdapter.dll
SynaEFIResDll.dll
Synaptics Fingerprint Manager.lnk
SynapticsFingerprintManager.exe
SynapticsFingerprintManager.exe.config
synaumdf.cat
synaWudfBioUsb.dll
synaWudfBioUsbHPProd.inf
```

### 11.1 Exact hardware match confirmed

The INF explicitly binds the package to:

```text
USB\VID_06CB&PID_00B7
```

The install sections also include the firmware copy group.

### 11.2 Exact firmware-extension confirmed

The INF contains:

```text
[FWextCopy]
6_07f_hp_cmit_mis_qm.xpfwext
```

and lists the same file under the source files.

This confirms that the firmware-extension file hard-coded by MR !626 for `06cb:00b7` is not a guessed neighboring artifact: it is the exact firmware-extension shipped by the matching Synaptics Windows driver package.

The file is copied verbatim; no INF rename or alternate companion firmware file was found.

### 11.3 Windows DLL string inspection

Simple string inspection of the main Windows binaries found firmware-related symbols including:

```text
CBiometricDevice::OnGetFirmwareVersion
CBiometricDevice::OnUpdateFirmware
CBiometricDevice::UpdateFirmwareExtension
FirmwareVersion =
GetSystemFirmwareTable
.xpfwext
```

No obvious string references to Linux-side names such as:

```text
init.bin
reset.bin
db_write_enable.bin
```

were found.

This suggests the Linux data blobs are not merely Windows files with different names.

---

## 12. Source of `libfprint-validity-data` discovered

The PPA source package identifies the upstream data repository as:

```text
https://gitlab.freedesktop.org/ggiesen/libfprint-validity-data
```

The source tarball was downloaded and inspected locally.

Important files include:

```text
generate_data.py
src/blobs_90.py
src/blobs_97.py
src/blobs_9a.py
src/blobs_9d.py
src/init_flash.py
src/tls.py
```

This was an important breakthrough because it explains exactly how the published `.bin` files are made.

---

## 13. How `generate_data.py` works

`generate_data.py` explicitly says it generates libfprint Validity data files from python-validity source extracts.

Its PID mapping is:

```text
90 -> 138a:0090
97 -> 138a:0097
9a -> 06cb:009a
9d -> 138a:009d
```

There is no `b7` entry.

The variable-to-output mapping is:

```text
init_hardcoded             -> init.bin
init_hardcoded_clean_slate -> init_clean_slate.bin
reset_blob                 -> reset.bin
db_write_enable            -> db_write_enable.bin
```

For each known device, the generator:

1. reads pre-existing hex payloads from `src/blobs_XX.py`,
2. decodes the hex into raw bytes,
3. appends an HMAC-SHA256 integrity trailer,
4. writes the corresponding `.bin` file.

The HMAC key is intentionally compiled into both the generator and driver; its role is corruption/tampering detection rather than secrecy.

Common partition signatures, TLS material, CA data, and firmware public-key coordinates are generated separately from `init_flash.py`, `tls.py`, and driver constants.

### Important conclusion

The generator **does not derive a device initialization sequence from VID/PID** and it does not extract `init.bin` from the Windows driver.

It only packages already-known protocol payloads.

Therefore adding `00b7` to the `PIDS` table alone would accomplish nothing unless a corresponding real `blobs_b7.py` payload definition existed.

---

## 14. Inspection of `src/blobs_9a.py`

The closest same-vendor example, `06cb:009a`, was inspected.

It defines four large opaque hex payloads:

```text
init_hardcoded
init_hardcoded_clean_slate
reset_blob
db_write_enable
```

These payloads are not small configuration structures. They are substantial pre-recorded binary command/data sequences beginning with protocol-looking data such as `060200...` and extending for hundreds or thousands of bytes.

This materially changes the interpretation of the missing `00b7` data:

> The missing `06cb_00b7/init.bin` is not something that can be responsibly synthesized by changing the PID, copying a short table entry, or trivially editing the `009a` payload.

`blobs_9a.py` gives us a reference format and confirms the packaging model, but it does **not** provide evidence that its payload is compatible with `00b7`.

Because MR !626 identifies the HP G6 `00b7` reader as a `57K0` / sensor-ID `0x0d51` family device, the next useful question is whether a legitimate 57K0 initialization payload exists elsewhere in python-validity history, another package revision, related hardware support, or upstream development artifacts.

Blindly reusing `06cb:009a` remains intentionally out of scope for Path 1 because it could send the wrong device-specific protocol sequence to the reader.

---

## 15. What is now proven

### Proven successful

- The reader is physically present as `06cb:00b7`.
- Stable Linux Mint/libfprint does not expose it through a usable fingerprint driver.
- MR !626 contains explicit `00b7` support logic.
- MR !626 builds completely on this Mint/Noble system (`120/120`).
- The build-tree library recognizes the physical reader and selects `libfprint-validity`.
- USB access works when temporary elevated permissions are supplied.
- Driver initialization proceeds until external Validity device data is requested.
- The available `libfprint-validity-data` package lacks `06cb_00b7`.
- The matching Windows package is confirmed by INF hardware ID `USB\VID_06CB&PID_00B7`.
- The matching Windows package contains the exact MR !626 firmware extension `6_07f_hp_cmit_mis_qm.xpfwext`.
- The data-package source and generator have been found.
- The generator packages pre-existing hard-coded device protocol payloads rather than deriving them automatically.
- `06cb:009a` has explicit large payload definitions, but there is no equivalent `b7` definition in the current source package.

### Not yet proven

- Existence/location of a legitimate `00b7` / 57K0 initialization payload.
- Successful device initialization past `init.bin` loading.
- Whether the confirmed `.xpfwext` will be needed in the reader's current firmware state.
- Fingerprint capture.
- Enrollment.
- Verification.
- fprintd integration.
- PAM/login/sudo authentication.

---

## 16. Current blocker, now more precisely defined

The blocker is no longer simply:

```text
"Find libfprint-validity-data"
```

and it is not merely:

```text
"Find the Windows firmware"
```

The Windows firmware extension has now been found and independently confirmed against the exact hardware package.

The real remaining data blocker is:

> **Locate a legitimate device initialization payload equivalent to python-validity's `init_hardcoded` for the `06cb:00b7` / HP G6 / 57K0 family, then package it in the format expected by MR !626 as `06cb_00b7/init.bin`.**

The existing generator already explains how to add the HMAC and output-file structure once the correct underlying payload is known.

---

## 17. Path 1 next investigation

The next investigation should remain non-invasive and source-oriented.

Good Path 1 leads include:

1. Search python-validity history/branches/issues for `00b7`, `57K0`, `0xd51`, HP G6, or the exact firmware name.
2. Search older/newer `libfprint-validity-data` revisions for a `blobs_b7.py` or 57K0 payload.
3. Inspect MR !626 discussion/commits for the hardware-validation source behind its `00b7` comments.
4. Compare related 57K0-family devices only to identify provenance or shared known data — **not** to blindly transmit another device's init payload.
5. Keep the confirmed Windows `.xpfwext` available for later build-tree testing once the mandatory init-data stage is solved.

### Path 1 stop condition

If obtaining the correct payload requires:

- capturing Windows USB traffic,
- reverse-engineering proprietary command sequences from DLL machine code,
- experimentally modifying/transmitting unknown initialization blobs,
- implementing missing protocol behavior in MR !626,

then Path 1 should stop and the work should be explicitly reclassified as **Path 2**.

---

## 18. System changes made

Most work remains under:

```text
~/fingerprint-path1
```

System development packages installed through APT:

- `libgusb-dev`
- `libusb-1.0-0-dev`
- `libjson-glib-dev`
- `libssl-dev`
- `gobject-introspection`

The experimental MR !626 libfprint driver has **not** been installed over the system library.

No PAM configuration has been changed.

No permanent udev rule has been added.

USB access testing used temporary process elevation.

The Windows driver was only downloaded and extracted as evidence/data; no Windows components were installed on Linux.

---

## 19. Current project state in one sentence

> **The native libfprint MR !626 driver builds completely and recognizes the HP EliteBook 840 G6 `06cb:00b7` reader; the exact Windows firmware extension has now been confirmed and obtained, and the `libfprint-validity-data` generator has been traced to pre-existing python-validity protocol blobs, leaving one sharply defined Path 1 blocker: locating the legitimate `00b7`/57K0 `init_hardcoded` payload needed to create `06cb_00b7/init.bin` before enrollment can proceed.**
