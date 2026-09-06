# Fingerprint Reader on HP EliteBook 840 G6 — Native Linux Investigation Log

**Project:** Native Linux fingerprint support on Linux Mint  
**Machine:** HP EliteBook 840 G6  
**Sensor:** Synaptics `06cb:00b7` — Fingerprint reader [HP G6]  
**OS:** Linux Mint 22.3 (Zena), Ubuntu Noble base  
**Kernel during testing:** `7.0.0-30-generic`  
**Current target:** native libfprint MR !626 Validity driver  
**Current state:** **Native enrollment/verification and fprintd enrollment/verification are all proven.** Linux Mint's normal `fprintd` service successfully loads the staged known-good MR !626 libfprint, detects the `06cb:00b7` sensor, completes right-index enrollment, matches the enrolled right index finger, and rejects a different finger. The next phase is PAM integration for daily authentication.

---

## 1. Goal

Make the built-in fingerprint reader work natively under Linux Mint through libfprint/fprintd/PAM for:

- desktop login,
- lock-screen unlock,
- `sudo`,
- other appropriate PAM-backed authentication paths.

Milestones:

1. libfprint recognizes and opens the sensor. **DONE**
2. Finger detection and capture work. **DONE**
3. Full native enrollment succeeds. **DONE**
4. Correct-finger native verification succeeds. **DONE**
5. Wrong-finger native verification rejects. **DONE**
6. `fprintd` sees the sensor. **DONE**
7. `fprintd` enrollment succeeds. **DONE**
8. `fprintd` correct-finger verification succeeds. **DONE**
9. `fprintd` wrong-finger rejection succeeds. **DONE**
10. PAM / sudo / login / lock-screen integration. **NEXT**
11. Reboot and suspend/resume stability.

---

## 2. Proven native driver baseline

The stock Mint/Noble stack returned:

```text
No devices available
```

The exact USB device is:

```text
06cb:00b7 Synaptics, Inc. Fingerprint reader [HP G6]
```

The known-good native source is libfprint MR !626 at:

```text
0fd78560a245eebec1c93e71ee1f29b15ec1be67
```

The driver identifies the hardware as:

```text
Device: 57K0 FM-3439-001 (type=0x0d51)
Sensor type: 0x0d51, 120 bytes/line, 2x repeat
```

The build completed successfully and no `ninja install` has been performed.

---

## 3. Validity data that proved necessary

Device-specific files:

```text
06cb_00b7/init.bin
06cb_00b7/db_write_enable.bin
```

Shared files:

```text
partition_sig_standard.bin
partition_sig_0090.bin
ca_pubkey.bin
tls_password.bin
gwk_sign.bin
fw_pubkey_x.bin
fw_pubkey_y.bin
```

`reset.bin` and `init_clean_slate.bin` were not required.

The exact known-good binary bundle is preserved in the repository under:

```text
FingerPrint_Sensor/permanent-data/validity/
```

with SHA-256 verification.

---

## 4. Native libfprint proof

The build-tree driver successfully completed firmware communication, TLS/session establishment, sensor identification, calibration, repeated real capture, enrollment, correct-finger matching, and wrong-finger rejection.

Successful enrollment ended with:

```text
ENROLL_NUM_STATES completed successfully
Print for finger FP_FINGER_RIGHT_INDEX enrolled
```

Correct finger:

```text
MATCH!
```

Wrong finger:

```text
NO MATCH!
```

This closed the hardware/driver reverse-engineering phase.

---

# Phase 2 — fprintd integration

## 5. Mint fprintd service layout

The installed daemon is:

```text
/usr/libexec/fprintd
```

and the service file is:

```text
/usr/lib/systemd/system/fprintd.service
```

The service has hardening enabled, including:

```text
ProtectHome=true
```

---

## 6. ABI / loader compatibility

Mint's `fprintd` links against:

```text
libfprint-2.so.2
```

The MR !626 build reports the same SONAME:

```text
Library soname: [libfprint-2.so.2]
```

A loader test with `LD_LIBRARY_PATH` successfully redirected `fprintd` to the build-tree library.

---

## 7. Reversible staged library integration

Instead of replacing Mint's system libfprint, the known-good build was staged under:

```text
/usr/local/lib/fprintd-validity/
```

A systemd drop-in was created at:

```text
/etc/systemd/system/fprintd.service.d/validity.conf
```

containing:

```ini
[Service]
Environment=LD_LIBRARY_PATH=/usr/local/lib/fprintd-validity
```

After daemon reload/restart, the environment was confirmed active.

This does not overwrite `/lib/x86_64-linux-gnu/libfprint-2.so.2`.

---

## 8. fprintd device detection

Running:

```bash
fprintd-list "$USER"
```

returned one device and identified:

```text
Validity VCSFW Fingerprint Sensor
```

This proved that Mint's normal `fprintd` service was loading the staged MR !626 library and exposing the sensor over D-Bus.

---

## 9. fprintd enrollment blocker: ProtectHome

The first enrollment attempt failed with:

```text
Required file init.bin not found for 06cb:00b7
```

The Validity paths under `/usr/local/share/libfprint/validity/` were symlinks into `/home/asif/...`.

Because `fprintd.service` has:

```text
ProtectHome=true
```

those symlinks could not be followed by the daemon.

The fix was to replace them with real root-owned files under `/usr/local/share/libfprint/validity/` using `sudo install -m 0644`.

---

## 10. fprintd enrollment success

After installing the Validity files as real system files and restarting `fprintd`:

```bash
fprintd-enroll -f right-index-finger "$USER"
```

completed successfully with:

```text
Enroll result: enroll-completed
```

This proved full system-level enrollment through Linux Mint's normal `fprintd` service.

---

## 11. MAJOR PHASE 2 MILESTONE: fprintd verification succeeds

Two `fprintd-verify` tests were performed using:

```bash
fprintd-verify -f right-index-finger "$USER"
```

### Correct finger

The enrolled right index finger produced:

```text
Verify result: verify-match (done)
```

### Wrong finger

A different finger produced:

```text
Verify result: verify-no-match (done)
```

This proves the complete `fprintd` path end to end: detection, enrollment, correct-finger acceptance, and wrong-finger rejection.

At this point, the remaining work is no longer about the sensor or `fprintd`; it is PAM/system authentication integration.

---

## 12. Current reversible system integration

```text
/usr/local/lib/fprintd-validity/
/etc/systemd/system/fprintd.service.d/validity.conf
/usr/local/share/libfprint/validity/...
```

The distro libfprint has not been overwritten.

No `ninja install` has been performed.

No PAM configuration has been changed yet.

---

## 13. Current proof matrix

```text
Physical sensor detection                 PASS
Native driver open                       PASS
TLS/session                              PASS
Calibration                              PASS
Native enrollment                        PASS
Native correct-finger verify             PASS
Native wrong-finger rejection            PASS
fprintd loads staged MR !626 library      PASS
fprintd detects 06cb:00b7                 PASS
fprintd system-level enrollment           PASS
fprintd correct-finger verification       PASS
fprintd wrong-finger rejection            PASS
PAM / sudo                                NEXT
Desktop login / lock screen               PENDING
Reboot persistence                        PENDING
Suspend/resume                            PENDING
Rollback documentation                    PENDING
```

---

## 14. Immediate next milestone

Proceed to PAM integration carefully.

Before changing authentication:

1. inspect Mint's fingerprint PAM profile;
2. inspect the current auth stack;
3. keep password authentication available as fallback;
4. enable fingerprint auth in a reversible way;
5. test `sudo` first before login/lock-screen changes.

---

## 15. Current project state in one sentence

> **The HP EliteBook 840 G6 `06cb:00b7` fingerprint reader is now proven end to end through Linux Mint's actual `fprintd` service: the daemon loads the staged MR !626 library, sees the sensor, enrolls the right index finger, accepts that finger with `verify-match`, and rejects a different finger with `verify-no-match`; the next phase is PAM integration for daily authentication.**
