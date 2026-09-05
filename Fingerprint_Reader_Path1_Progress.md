# Fingerprint Reader on HP EliteBook 840 G6 — Native Linux Investigation Log

**Project:** Native Linux fingerprint support on Linux Mint  
**Machine:** HP EliteBook 840 G6  
**Sensor:** Synaptics `06cb:00b7` — Fingerprint reader [HP G6]  
**OS:** Linux Mint 22.3 (Zena), Ubuntu Noble base  
**Kernel during testing:** `7.0.0-30-generic`  
**Current target:** native libfprint MR !626 Validity driver  
**Current state:** MR !626 builds completely, recognizes the physical reader, reads its firmware successfully, confirms the firmware extension is already loaded, and currently stops at the mandatory external `06cb_00b7/init.bin` data stage. Recent upstream python-validity work now provides strong evidence that the reader is the `0xd51` / 57K0 variant and that an existing initialization blob can be reused rather than requiring a unique `blobs_b7.py`.

---

## 1. Goal

The built-in fingerprint reader works correctly under Windows but is not exposed by the stable fingerprint stack shipped with Linux Mint.

The objective is to make the reader work natively under Linux with the normal libfprint/fprintd stack and, once enrollment and verification are proven, integrate it safely with desktop/login authentication.

Success means:

1. libfprint recognizes and opens the sensor.
2. Enrollment succeeds.
3. Verification distinguishes the correct finger from an incorrect finger.
4. fprintd integration works reliably.
5. PAM/login/sudo integration is attempted only after the lower-level tests are stable.

---

## 2. Investigation phases

The work was initially described as two paths:

- **Path 1:** practical reuse/integration of existing native Linux support.
- **Path 2:** deeper protocol/driver engineering if existing support is incomplete.

This distinction is still useful as a complexity marker, but it is **not a hard project boundary**. If practical integration naturally requires source modifications, protocol analysis, USB tracing, or other deeper work, that will be treated as the next engineering phase of the same fingerprint project rather than as a separate project that must be abandoned or restarted.

The preference remains: use existing validated behavior wherever possible before inventing new behavior.

---

## 3. Baseline system state

Installed fingerprint packages included:

- `fprintd`
- `libfprint-2-2`
- `libfprint-2-tod1`
- `libpam-fprintd`

The stock test returned:

```text
No devices available
```

USB enumeration confirmed:

```text
06cb:00b7 Synaptics, Inc. Fingerprint reader [HP G6]
```

The device is vendor-specific USB hardware with bulk and interrupt endpoints. The sensor is physically present, and the same hardware works under Windows.

---

## 4. Why the old python-validity route was not chosen as the runtime solution

An older Linux route for some Validity/Synaptics devices is `python-validity`.

Earlier reports for `06cb:00b7` showed that simply adding the USB ID and forcing nearby sensor profiles did not provide reliable support. Because of that, python-validity was not selected as the main runtime architecture.

The active target remains:

```text
libfprint MR !626 native Validity driver
        ↓
      fprintd
        ↓
Linux enrollment / verification
```

However, recent python-validity development has become extremely valuable as a **reference implementation and evidence source**. This does not mean the project is reverting to the old python-validity architecture. Instead, working python-validity research for the same hardware family is being used to understand initialization blobs, sensor identity, firmware behavior, and protocol quirks that can inform the native libfprint path.

---

## 5. Discovery of libfprint MR !626

libfprint merge request **!626** contains a native Validity/Synaptics implementation with explicit references to the exact sensor.

Important evidence in the branch includes:

- `VALIDITY_DEV_B7` for `06cb:00b7`,
- HAL support for PID `0x00b7`,
- HP EliteBook 840 G6 references,
- firmware-extension handling specifically including `06cb:00b7`,
- a sensor-family mapping associating HP G6 `06cb:00b7` with the 57K0 family and sensor ID `0x0d51`.

Relevant files include:

```text
libfprint/drivers/validity/validity.h
libfprint/drivers/validity/validity_fwext.c
libfprint/drivers/validity/validity_hal.c
libfprint/drivers/validity/validity_sensor.c
libfprint/drivers/validity/validity_data.c
```

This made MR !626 the strongest native candidate.

---

## 6. Isolated workspace and build policy

The investigation is kept primarily under:

```text
~/fingerprint-path1
```

Important subdirectories include:

```text
~/fingerprint-path1/libfprint
~/fingerprint-path1/tools-venv
~/fingerprint-path1/validity-data
~/fingerprint-path1/windows-driver
```

MR !626 was fetched into the local branch:

```text
mr-626
```

Meson and Ninja were initially installed inside a Python virtual environment.

The experimental libfprint driver has **not** been installed over the system libfprint. Build-tree execution is being used until enrollment and verification are proven.

No PAM configuration has been changed and no permanent udev rule has been added yet.

---

## 7. Build dependency history

Several failures were normal build-environment issues rather than driver failures.

### GUsb / libusb / json-glib

Locally extracted development packages produced fragile pkg-config/header paths, eventually causing missing-header failures such as:

```text
fatal error: gusb.h: No such file or directory
```

A controlled exception was made and normal APT development packages were installed:

- `libgusb-dev`
- `libusb-1.0-0-dev`
- `libjson-glib-dev`

### OpenSSL

Compilation then reached the Validity implementation and failed on:

```text
openssl/evp.h: No such file or directory
```

Installing `libssl-dev` resolved that blocker.

### GObject Introspection

A later failure occurred while generating `FPrint-2.0.gir` because `/usr/bin/g-ir-scanner` was missing. Installing `gobject-introspection` resolved this final tooling issue.

---

## 8. Major build success

After a clean Meson configuration and the required development packages, Ninja completed the full build:

```text
[120/120]
```

The build compiled and linked Validity components covering:

- protocol communication,
- sensor handling,
- HAL/device mapping,
- firmware extension support,
- TLS,
- pairing,
- enrollment,
- verification,
- capture,
- database handling.

This proved that MR !626 is buildable on the current Mint/Noble environment without writing a new driver from scratch.

---

## 9. Build-tree runtime tests

The build-tree enrollment example was run directly against the newly built libfprint.

The first hardware failure was USB permissions:

```text
USB error on device 06cb:00b7 : Access denied
```

Debug output showed the `validity` driver being selected for the physical reader, proving that MR !626 recognizes the device.

A one-off elevated test was then used instead of creating a permanent udev rule. With USB access available, initialization progressed further and stopped at:

```text
Device data files not found for 06cb:00b7.
Install the libfprint-validity-data package.
```

The driver searches locations including:

```text
/usr/share/libfprint/validity/
/usr/local/share/libfprint/validity/
```

The per-device directory is expected to be:

```text
06cb_00b7/
```

Known per-device filenames include:

```text
init.bin
init_clean_slate.bin
reset.bin
db_write_enable.bin
```

`init.bin` is mandatory for the current open path; the other per-device blobs are optional in the loading logic.

---

## 10. Published libfprint-validity-data package

A `libfprint-validity-data` package exists in the `m-jedrasik/libfprint-validity` PPA, but that PPA does not support Noble. Rather than force a foreign repository onto the system, the package was downloaded and extracted locally.

The investigated package was:

```text
libfprint-validity-data
Version: 0.1.0-1ppa2~resolute1
Architecture: all
```

It contains per-device directories for:

```text
06cb_009a
138a_0090
138a_0097
138a_009d
```

but not:

```text
06cb_00b7
```

Therefore simply installing the available data package would not solve the current runtime blocker.

---

## 11. Data integrity format

MR !626 verifies the data package using an HMAC-SHA256 trailer.

The HMAC key is intentionally included in both the generator and driver and is used for integrity checking rather than secrecy.

This means the `.bin` format is understood:

```text
raw protocol payload
        +
32-byte HMAC-SHA256 trailer
```

The remaining problem is therefore not how to format `init.bin`; it is identifying a validated underlying initialization payload for the sensor family.

---

## 12. Matching Windows driver package

The exact Windows driver for the hardware was obtained from the Microsoft Update Catalog and extracted under:

```text
~/fingerprint-path1/windows-driver/extracted
```

The package binds explicitly to:

```text
USB\VID_06CB&PID_00B7
```

It contains the firmware extension:

```text
6_07f_hp_cmit_mis_qm.xpfwext
```

The INF copies this exact filename through its firmware-extension copy section. This independently confirms that MR !626's firmware mapping for the HP G6 sensor is correct.

Simple string inspection of the Windows DLLs found firmware-related symbols such as:

```text
CBiometricDevice::OnGetFirmwareVersion
CBiometricDevice::OnUpdateFirmware
CBiometricDevice::UpdateFirmwareExtension
FirmwareVersion =
GetSystemFirmwareTable
.xpfwext
```

but no obvious Windows files or strings corresponding directly to Linux-side names such as `init.bin`, `reset.bin`, or `db_write_enable.bin`.

---

## 13. Source of libfprint-validity-data

The PPA source package points to:

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

`generate_data.py` maps existing python-validity-style payload definitions into libfprint `.bin` files.

The original PID map is:

```text
90 -> 138a:0090
97 -> 138a:0097
9a -> 06cb:009a
9d -> 138a:009d
```

The variable mapping is:

```text
init_hardcoded             -> init.bin
init_hardcoded_clean_slate -> init_clean_slate.bin
reset_blob                 -> reset.bin
db_write_enable            -> db_write_enable.bin
```

The generator does **not** derive initialization commands from the USB PID and does not extract them from the Windows driver. It packages already-known payloads and appends the required HMAC.

---

## 14. Initial inspection of blobs_9a.py

`src/blobs_9a.py` contains large opaque protocol payloads for:

```text
init_hardcoded
init_hardcoded_clean_slate
reset_blob
db_write_enable
```

At that stage of the investigation there was not yet enough evidence to justify sending the `009a` initialization payload to `00b7`, so reusing it was deliberately postponed.

That conclusion has now been refined by newer upstream evidence described below.

---

## 15. Important upstream breakthrough: python-validity PR #256

Recent upstream work in `uunicorn/python-validity` PR **#256**, titled roughly around adding support for sensor type `0xd51`, directly covers:

```text
138a:00ab — HP EliteBook 840 G5
06cb:00b7 — HP G6-series devices
```

This is highly relevant even though python-validity is not the target runtime stack, because it documents successful behavior on the same chip family and exact USB ID.

The PR explains that earlier attempts failed after adding the USB ID, reusing nearby blobs, and spoofing the sensor profile because the real remaining blocker was a protocol-level capture interrupt difference.

For the `0xd51` family, the device can skip the conventional `b[0] = 2` finger-detected interrupt and move directly from the type-0 start acknowledgement to `b[0] = 3` capture events. Once the capture loop handles this correctly, the rest of the existing pipeline works.

The same work aliases `0xd51` to an existing `0x199` sensor profile/capture program where required, while keeping the real sensor type for the special interrupt behavior.

This is strong evidence that the 57K0/0xd51 family is close to existing Validity implementations and does not require an entirely independent stack.

---

## 16. Existing blob reuse is now supported by evidence

PR #256's blob handling provides a critical correction to the earlier assumption that `06cb:00b7` necessarily requires a unique `blobs_b7.py`.

Current development routes `06cb:00b7` through an existing initialization-blob family rather than requiring a new dedicated normal-init payload.

The branch contains logic equivalent to:

```text
06cb:009a -> blobs_9a
06cb:00b7 -> blobs_9a
```

with comments explaining that the established non-destructive initialization data are retained for `00b7` until a complete Windows provisioning capture exists for every destructive/reset path.

Separately, the `138a:00ab` 0xd51 device gained a `blobs_d51.py` where the reset payload came from a Windows USB capture, while normal initialization and write-enable data are reused from existing profiles.

This distinguishes two concepts that were previously being treated as one:

- normal initialization payloads can be shared across compatible chips,
- reset/clean-slate/provisioning payloads may require more device-specific validation.

That matters because MR !626 currently blocks on mandatory `init.bin`, not on `reset.bin`.

The first future test should therefore remain conservative: create and expose only the validated/reused normal `init.bin`, not destructive/reset data.

---

## 17. Real-world exact-USB-ID validation

The upstream issue/PR discussion contains a real-world confirmation for:

```text
06cb:00b7
sensor type 0xd51
```

on an HP ProBook 650 G7.

The reporter confirmed:

- firmware extraction of `6_07f_hp_cmit_mis_qm.xpfwext`,
- successful `fprintd-enroll`,
- successful system authentication,
- working PAM/GDM/sudo fingerprint authentication.

This is especially valuable because it proves that `06cb:00b7 + 0xd51` is not merely theoretical or inferred from neighboring hardware.

The same upstream discussion notes that `06cb:00b7` has appeared with more than one underlying silicon variant in the wild, including `0xd51` and `0x969`, so identifying the actual device variant matters.

---

## 18. Runtime firmware fingerprint identifies this machine as the 0xd51/57K0 case

A new build-tree runtime log was captured with full Validity debugging enabled.

During probe, MR !626 reported:

```text
Validity sensor firmware:
  Version: 6.7
  Product: 48
  Build Num: 164
  Build Time: 1415491824
```

It then selected:

```text
Validity VCSFW Fingerprint Sensor
```

and proceeded through open states 0–5.

The runtime log also explicitly reported:

```text
Firmware extension is loaded
```

before entering state 6 and failing only because the external device data were absent.

The firmware tuple:

```text
Version 6.7
Product 48
Build 164
Build Time 1415491824
```

matches the reference `0xd51` / 57K0 device documented in the successful upstream work.

That reference identifies:

```text
identify_sensor name: 57K0 FM- 154-120
device_info.type: 0xd51
RomInfo: timestamp=1415491824, build=164, major=6, minor=7, product=48
```

This provides strong evidence that the HP EliteBook 840 G6 reader in this investigation is the `0xd51` / 57K0 variant rather than the alternate `0x969` variant reported under the same USB PID on some other HP systems.

---

## 19. Current interpretation of the blocker

The current failure remains:

```text
Device data files not found for 06cb:00b7
```

but the meaning of that failure has changed substantially.

Earlier interpretation:

> A unique and currently missing `00b7` initialization payload may need to be discovered or extracted.

Current evidence-backed interpretation:

> The `06cb:00b7` reader is strongly identified as the 0xd51/57K0 variant, and working upstream implementations reuse established non-destructive initialization data for this family. Therefore a safe next experiment is to package only the known normal initialization payload as `06cb_00b7/init.bin`, with the correct HMAC, and retry MR !626 without supplying reset/clean-slate data.

This is a materially stronger basis for the experiment than simply guessing that `009a` might be close enough.

---

## 20. What is proven now

### Proven

- Physical reader is `06cb:00b7`.
- Stock Mint/Noble libfprint does not expose it normally.
- MR !626 explicitly contains support for this PID/family.
- MR !626 builds completely (`120/120`).
- The build-tree driver recognizes the physical reader.
- Temporary root access removes the USB-permission blocker.
- The device firmware is read successfully as version 6.7, product 48, build 164, timestamp 1415491824.
- The firmware tuple matches the known `0xd51` / 57K0 reference device.
- MR !626 reports that the firmware extension is already loaded.
- The exact Windows driver package contains the exact MR !626 firmware-extension filename.
- The available libfprint-validity-data package lacks a `06cb_00b7` directory.
- The data-package generator and HMAC format are understood.
- Recent upstream work supports `06cb:00b7` and has real-world successful enrollment/authentication reports.
- Existing non-destructive initialization blobs can be reused across this family in working upstream implementations.

### Not yet proven on this machine

- MR !626 opening successfully after providing `init.bin`.
- Whether MR !626's own native handling covers all `0xd51` interrupt quirks once initialization proceeds.
- Fingerprint image/capture behavior.
- Enrollment.
- Verification.
- Reliable fprintd integration.
- PAM/login/sudo authentication.

---

## 21. Immediate next experiment

The next experiment should be deliberately narrow and non-destructive:

1. Use a small helper script in the project workspace to read the known `init_hardcoded` payload from the existing blob source.
2. Append the HMAC-SHA256 trailer using the same integrity key as `generate_data.py`.
3. Write only:

   ```text
   output/06cb_00b7/init.bin
   ```

4. Verify that generated file using the package's own verifier before exposing it to MR !626.
5. Do **not** generate or install `reset.bin`, `init_clean_slate.bin`, or other destructive/provisioning data yet.
6. Retry the build-tree native MR !626 enrollment path and record the next runtime state/error.

VS Code can be used for the helper script so the code remains visible, editable, and easy to keep under `~/fingerprint-path1` instead of embedding a long Python heredoc in the shell history.

---

## 22. System changes made

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

The Windows driver was downloaded and extracted for investigation only; no Windows components were installed on Linux.

---

## 23. Current project state in one sentence

> **The native libfprint MR !626 driver builds completely and recognizes the HP EliteBook 840 G6 `06cb:00b7` reader; runtime firmware data strongly identifies this machine as the supported `0xd51`/57K0 variant, the exact firmware extension is already loaded, and recent successful upstream work shows that established non-destructive initialization data can be reused for this family, making the next controlled step to generate only `06cb_00b7/init.bin` and retry the native MR !626 open/enrollment path.**