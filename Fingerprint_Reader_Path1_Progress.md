# Fingerprint Reader on HP EliteBook 840 G6 — Path 1 Progress Log

**Project:** Native Linux fingerprint support on Linux Mint  
**Machine:** HP EliteBook 840 G6  
**Sensor:** Synaptics `06cb:00b7` — Fingerprint reader [HP G6]  
**OS:** Linux Mint 22.3 (Zena), Ubuntu Noble base  
**Kernel during testing:** `7.0.0-30-generic`  
**Status:** Native driver successfully built and sensor detected; runtime is currently blocked by missing device-specific Validity data for `06cb:00b7`.

---

## 1. Why this work started

The fingerprint reader in the HP EliteBook 840 G6 works correctly under Windows, but Linux Mint did not expose it through the normal fingerprint stack.

The system already had the standard fingerprint packages installed:

- `fprintd`
- `libfprint-2-2`
- `libfprint-2-tod1`
- `libpam-fprintd`

Despite that, the normal user-facing test returned:

```text
No devices available
```

This established the first important fact: the hardware itself was present and functional, but the stable libfprint stack shipped with Linux Mint/Ubuntu Noble did not provide a working driver for this exact sensor.

The USB device was confirmed as:

```text
06cb:00b7 Synaptics, Inc. Fingerprint reader [HP G6]
```

The device is vendor-specific USB hardware with bulk and interrupt endpoints. There was no sign that the device was physically absent or disabled.

---

## 2. Two-path strategy

To avoid turning a practical setup attempt into an endless reverse-engineering project, the work was deliberately divided into two possible paths.

### Path 1 — practical native attempt

The goal of Path 1 is to make the existing hardware work using a native Linux/libfprint implementation without developing a new fingerprint driver from scratch.

Success criteria:

1. Linux enumerates the sensor through a real libfprint driver.
2. The sensor can be opened successfully.
3. A fingerprint can be enrolled.
4. The enrolled fingerprint can be verified.

Path 1 may include:

- building an existing libfprint development branch,
- installing normal development dependencies,
- using firmware or device-data files that already exist for the hardware,
- inspecting the matching Windows driver package for firmware/configuration artifacts.

Path 1 should stop if success requires substantial protocol reverse engineering, USB tracing, or implementation of new driver logic.

### Path 2 — future open-source driver work

If Path 1 cannot succeed without real driver development, the work should be reclassified as Path 2.

That would be a separate development project involving tasks such as protocol investigation, USB transaction analysis, source modifications, quirks, tests, and potentially upstream contribution.

Path 2 has **not** started.

---

## 3. Early route considered and rejected: python-validity

An older Linux route for some Validity/Synaptics sensors is `python-validity`.

Research showed historical reports involving the HP EliteBook 840 G6 and the same `06cb:00b7` device where the older python-validity stack did not match/support the sensor correctly.

Because of that, the project did **not** proceed by trying to revive the older python-validity daemon as the main solution.

This distinction became important later because the newer driver also uses the word **Validity**, but it is a completely different architecture:

```text
Old route:
python-validity daemon
        ↓
      fprintd
```

The route currently being tested is:

```text
libfprint MR !626 native Validity driver
        ↓
      fprintd
        ↓
Linux enrollment / verification
```

The current work is therefore **not python-validity**.

---

## 4. Discovery of libfprint MR !626

The key breakthrough was finding an in-development libfprint merge request, **MR !626**, containing a native Validity/Synaptics driver.

The merge-request source explicitly contains support entries for the exact sensor:

```text
06cb:00b7
```

Important source references discovered inside the branch include:

- `libfprint/drivers/validity/validity.h`
- `libfprint/drivers/validity/validity_fwext.c`
- `libfprint/drivers/validity/validity_hal.c`
- `libfprint/drivers/validity/validity_sensor.c`

The source contains comments specifically naming the HP EliteBook 840 G6 and `06cb:00b7`.

Examples of what was found:

- a device identifier for `VALIDITY_DEV_B7`,
- a HAL entry using PID `0x00b7`,
- a sensor-family mapping for the HP G6 series,
- firmware-extension handling specifically including `06cb:00b7`.

This was much stronger evidence than the stable libfprint tree, where `00b7` appeared only in a generic USB hardware list and was not registered to a usable fingerprint driver.

At this point, MR !626 became the main Path 1 candidate.

---

## 5. Isolated build workspace

To keep the experiment easy to understand and mostly removable, the working area was created under:

```text
~/fingerprint-path1
```

The libfprint source was placed under:

```text
~/fingerprint-path1/libfprint
```

MR !626 was fetched into a local branch named:

```text
mr-626
```

A Python virtual environment was also created for the build tools:

```text
~/fingerprint-path1/tools-venv
```

Meson and Ninja were installed inside that environment instead of immediately installing them globally.

This allowed the actual driver source and build tooling to remain largely contained inside the project workspace.

---

## 6. Build dependency phase — what failed and why

The first significant obstacle was not the fingerprint code. It was the development environment.

The machine had runtime libraries installed, but several corresponding development headers and pkg-config files were missing.

### 6.1 GUsb / libusb / json-glib

The first Meson configuration failed because the `gusb` development dependency could not be found.

Initially, development `.deb` packages were downloaded and extracted locally inside the project directory to avoid modifying the system.

That proved that the required metadata and headers were available, but it introduced an important problem: the extracted `.pc` pkg-config files still contained paths such as:

```text
/usr/include/gusb-1
/usr/include/libusb-1.0
/usr/include/json-glib-1.0
```

while the real extracted headers were under `~/fingerprint-path1/...`.

As a result, Ninja failed with errors like:

```text
fatal error: gusb.h: No such file or directory
```

This was a build-environment problem, not a fingerprint-driver problem.

After trying to preserve complete local isolation, a small and controlled exception was made: normal system development packages were allowed where they simplified the build substantially.

The following development packages were installed through APT:

- `libgusb-dev`
- `libusb-1.0-0-dev`
- `libjson-glib-dev`

Their headers were verified under `/usr/include`.

That removed the GUsb/libusb/json-glib blocker.

### 6.2 OpenSSL

Once the generic USB dependencies were fixed, compilation reached the actual Validity driver sources and failed on:

```text
openssl/evp.h: No such file or directory
```

This was progress: the compiler was now entering files such as the Validity protocol, TLS, firmware-extension, and pairing implementation.

`libssl-dev` was installed through APT and `/usr/include/openssl/evp.h` was verified.

After a clean Meson reconfiguration, the OpenSSL failure disappeared.

### 6.3 GObject Introspection

The next failure happened much later in the build, after the Validity code had compiled.

A locally extracted GObject Introspection wrapper attempted to execute:

```text
/usr/bin/g-ir-scanner
```

but the system executable was not present.

The build therefore failed while generating:

```text
FPrint-2.0.gir
```

This was again tooling, not driver logic.

The system `gobject-introspection` package was installed, and the required components were verified:

```text
/usr/bin/g-ir-scanner
/usr/libexec/gobject-introspection-bin/deb-elf-get-needed
```

A final clean Meson setup was then performed without the earlier custom pkg-config path workarounds.

---

## 7. Major success: MR !626 builds completely

After resolving the development dependencies, Ninja completed the full build:

```text
[120/120]
```

This is an important milestone.

The build successfully compiled the native Validity implementation, including components for:

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

The resulting libfprint shared library was linked successfully as well.

This means the native MR !626 driver is buildable on the current Linux Mint 22.3 / Noble environment once the required development packages are available.

No custom driver code had to be written to achieve this build.

---

## 8. First runtime test — the driver sees `06cb:00b7`

The build-tree enrollment example was launched directly against the newly built library rather than installing it system-wide.

The program reached the normal finger-selection menu, which confirmed the example itself was running correctly.

The right index finger was selected for testing.

The first runtime attempt then produced a USB permission error:

```text
USB error on device 06cb:00b7 : Access denied (insufficient permissions)
```

This failure was actually useful because the debug log showed:

```text
libfprint-validity-DEBUG
```

for the `06cb:00b7` sensor.

That proved something the stable system stack could not do:

> **MR !626 recognized the physical `06cb:00b7` reader and selected the native Validity driver for it.**

The earlier stable system test had simply returned `No devices available`.

The test was repeated once with elevated privileges only for the process, avoiding permanent udev changes at this stage.

This removed the USB permission blocker.

---

## 9. Second runtime test — driver opens far enough to request device data

With USB access available, the driver progressed further into its device-open state machine.

The next failure was:

```text
Device data files not found for 06cb:00b7.
Install the libfprint-validity-data package.
```

The driver searched locations including:

```text
/usr/share/libfprint/validity/
/usr/local/share/libfprint/validity/
```

This is the current Path 1 blocker.

It is important to distinguish this from earlier failures:

- the sensor is physically visible,
- the new driver is selected,
- USB permission can be satisfied,
- the native driver has built successfully,
- failure now occurs because a device-specific data package for `06cb:00b7` is missing.

This is therefore **not** a generic "driver not found" state anymore.

---

## 10. Investigation of the required Validity data

The MR !626 source was inspected to understand exactly what the driver expects.

### 10.1 Device-specific directory layout

For the current hardware, the per-device directory name is constructed from VID and PID:

```text
06cb_00b7
```

The expected location therefore becomes something like:

```text
/usr/share/libfprint/validity/06cb_00b7/
```

### 10.2 Per-device blob names

The driver knows these per-device filenames:

```text
init.bin
init_clean_slate.bin
reset.bin
db_write_enable.bin
```

Of these, `init.bin` is mandatory.

The others are treated as optional if absent.

### 10.3 Common Validity data

The data package also supports common files such as:

```text
partition_sig_standard.bin
partition_sig_0090.bin
ca_pubkey.bin
tls_password.bin
gwk_sign.bin
fw_pubkey_x.bin
fw_pubkey_y.bin
```

### 10.4 Integrity protection

These files are not arbitrary binary blobs.

`validity_data.c` verifies the packaged device data with an HMAC before using it. A corrupt or incompatible file is rejected.

This means copying an `init.bin` from a random neighboring sensor is not a sound solution even if the filename matches.

---

## 11. `libfprint-validity-data` package investigation

The natural next attempt was to obtain the dedicated `libfprint-validity-data` package used with the new Validity work.

A PPA was discovered that publishes the package, but attempting to add it normally on Linux Mint 22.3 / Noble failed because the PPA does not support Noble.

Rather than force a foreign repository onto the system, its package index was queried directly.

The exact package found was:

```text
libfprint-validity-data
Version: 0.1.0-1ppa2~resolute1
Architecture: all
```

The `.deb` was downloaded manually into the project workspace and extracted locally without installing it.

This kept the experiment controlled and avoided replacing the system libfprint stack.

### Result

The package contained per-device data for:

```text
06cb_009a
138a_0090
138a_0097
138a_009d
```

It also contained the common Validity data files.

However, it **did not contain:**

```text
06cb_00b7/
```

Therefore the currently published data package does not provide the required `init.bin` for the HP EliteBook 840 G6 reader.

This was another useful negative result: the problem is no longer "find the package"; the package itself simply does not ship the exact device payload we need.

---

## 12. Firmware-extension mapping for the HP device

MR !626 contains explicit firmware-extension logic for the HP variant.

For:

```text
06cb:00b7
```

the driver maps the firmware-extension filename to:

```text
6_07f_hp_cmit_mis_qm.xpfwext
```

The source comments identify this as an HP variant and specifically reference `06cb:00b7` / HP EliteBook 840 G6.

The firmware search paths include locations such as:

```text
/usr/share/libfprint/validity
/var/lib/python-validity
/var/run/python-validity
/usr/share/python-validity
```

This firmware extension is related to the sensor's firmware path, while the immediate runtime failure currently concerns the separate per-device data store (`init.bin`, etc.).

Both may become relevant during the next phase.

---

## 13. What has been proven so far

The work has already answered several important questions.

### Proven successful

- The HP EliteBook 840 G6 fingerprint reader is physically present as `06cb:00b7`.
- Stable Linux Mint/libfprint does not provide a usable driver for it.
- libfprint MR !626 contains explicit source support for this device.
- MR !626 can be configured and built successfully on Linux Mint 22.3 / Noble.
- The full Ninja build completes successfully (`120/120`).
- The resulting build-tree library can be loaded without installing it system-wide.
- MR !626 recognizes `06cb:00b7` and selects the native Validity driver.
- The sensor can be reached once USB permissions are provided.
- Runtime proceeds far enough into device open/initialization to request Validity device data.

### Not yet proven

- Successful device initialization beyond the missing data stage.
- Successful firmware-extension handling if it is required on this particular sensor state.
- Successful fingerprint capture.
- Successful enrollment.
- Successful verification.
- Reliable integration with `fprintd`.
- Login/sudo/PAM authentication.

PAM integration is intentionally postponed until enrollment and verification work reliably in the build-tree tests.

---

## 14. Current blocker

The current failure is specific and reproducible:

```text
Device data files not found for 06cb:00b7
```

The driver expects a device directory:

```text
06cb_00b7/
```

with at minimum:

```text
init.bin
```

The available `libfprint-validity-data` package does not contain this device directory.

No evidence has been found inside MR !626 of a tool that automatically generates the missing `06cb_00b7/init.bin` payload from scratch.

Because the data is integrity-checked and device-specific, borrowing another sensor's blob by guesswork is deliberately avoided.

---

## 15. Next phase — inspect the matching Windows driver package

Before escalating this work into Path 2 driver development, Path 1 has one strong remaining lead: the official Windows driver package for this exact reader.

The Windows hardware works correctly on the same laptop, so the matching Synaptics package may contain firmware, initialization data, OEM configuration, or other artifacts that can explain what Linux is missing.

The relevant Windows hardware identity is:

```text
USB\VID_06CB&PID_00B7
```

The matching Windows driver family has been identified as a Synaptics VFS7552/PurePrint fingerprint sensor package.

The next investigation should be performed under:

```text
~/fingerprint-path1/windows-driver/
```

### Planned Windows-driver investigation

1. Obtain the exact Windows driver package that supports `USB\VID_06CB&PID_00B7`.
2. Extract the package locally; do not install Windows components on Linux.
3. Inspect INF files to confirm the exact hardware mapping.
4. Search the extracted package for the expected HP firmware-extension name:

   ```text
   6_07f_hp_cmit_mis_qm.xpfwext
   ```

5. Search for binary/configuration data that may correspond to the required Linux-side `init.bin` and related initialization blobs.
6. Compare any discovered files with MR !626's parsing, expected sizes, and initialization flow.
7. Keep all experiments inside `~/fingerprint-path1` wherever practical.
8. Retry the build-tree enrollment test only after the missing data is understood and supplied correctly.

### Path 1 stop condition

If obtaining the required data turns into any of the following:

- reverse-engineering unknown USB transactions,
- capturing Windows USB traffic,
- creating a new initialization protocol,
- substantial changes to the MR !626 driver,
- implementing missing hardware behavior,

then Path 1 should stop.

That work belongs to **Path 2**, where the goal would explicitly become open-source driver development rather than practical installation.

---

## 16. System changes made during the experiment

Most work remains under:

```text
~/fingerprint-path1
```

However, several normal development packages were installed through APT after local-only dependency extraction became unnecessarily fragile:

- `libgusb-dev`
- `libusb-1.0-0-dev`
- `libjson-glib-dev`
- `libssl-dev`
- `gobject-introspection`

These are build/development dependencies. The experimental MR !626 libfprint driver itself has **not** been installed over the system library.

No PAM configuration has been changed for this experiment.

No permanent udev rule has been added at this stage.

The runtime USB-access test used temporary elevated privileges rather than immediately changing system permissions.

---

## 17. Current project state in one sentence

> **The native libfprint MR !626 driver now builds completely and successfully recognizes the HP EliteBook 840 G6 `06cb:00b7` fingerprint reader; the remaining Path 1 blocker is the absence of the device-specific Validity initialization data, so the next step is to inspect the exact Windows Synaptics driver package for firmware/configuration artifacts before considering any real driver-development work.**
