# Fingerprint Reader on HP EliteBook 840 G6 — Native Linux Investigation Log

**Project:** Native Linux fingerprint support on Linux Mint  
**Machine:** HP EliteBook 840 G6  
**Sensor:** Synaptics `06cb:00b7` — Fingerprint reader [HP G6]  
**OS:** Linux Mint 22.3 (Zena), Ubuntu Noble base  
**Kernel during testing:** `7.0.0-30-generic`  
**Current target:** native libfprint MR !626 Validity driver  
**Current state:** **Native enrollment/verification are proven and `fprintd` system integration has now crossed the enrollment milestone.** Linux Mint's normal `fprintd` service successfully loads the staged known-good MR !626 libfprint, detects the `06cb:00b7` sensor, and completes full right-index enrollment.

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
8. `fprintd` correct/wrong verification. **NEXT**
9. PAM / sudo / login / lock-screen integration.
10. Suspend/resume and long-term stability.

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

The build-tree driver successfully completed:

- firmware communication;
- firmware-extension detection;
- TLS handshake/session establishment;
- sensor identification;
- calibration;
- repeated real fingerprint capture;
- right-index enrollment;
- correct-finger match;
- different-finger rejection.

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

This later became important for the Validity data path.

---

## 6. ABI / loader compatibility check

Mint's `fprintd` links against:

```text
libfprint-2.so.2
```

The MR !626 build reports the same SONAME:

```text
Library soname: [libfprint-2.so.2]
```

A loader test using:

```bash
LD_LIBRARY_PATH="$HOME/fingerprint-path1/build/libfprint" \
ldd /usr/libexec/fprintd | grep -i fprint
```

successfully redirected `fprintd` to the build-tree library.

---

## 7. Reversible staged library integration

Instead of replacing Mint's system libfprint, the known-good build was staged under:

```text
/usr/local/lib/fprintd-validity/
```

with:

```text
libfprint-2.so.2 -> libfprint-2.so.2.0.0
libfprint-2.so.2.0.0
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

After:

```bash
sudo systemctl daemon-reload
sudo systemctl restart fprintd
```

this was confirmed with:

```text
Environment=LD_LIBRARY_PATH=/usr/local/lib/fprintd-validity
```

This is reversible and does not overwrite `/lib/x86_64-linux-gnu/libfprint-2.so.2`.

---

## 8. First fprintd detection success

Running:

```bash
fprintd-list "$USER"
```

returned:

```text
found 1 devices
Device at /net/reactivated/Fprint/Device/0
Using device /net/reactivated/Fprint/Device/0
User asif has no fingers enrolled for Validity VCSFW Fingerprint Sensor.
```

This proved that Mint's normal `fprintd` service was loading the staged MR !626 library and exposing the sensor over D-Bus.

---

## 9. fprintd enrollment blocker: systemd ProtectHome

The first enrollment attempt later failed with:

```text
Required file init.bin not found for 06cb:00b7
```

The cause was not missing data. The Validity paths under `/usr/local/share/libfprint/validity/` were symlinks into:

```text
/home/asif/fingerprint-path1/...
```

Because `fprintd.service` has:

```text
ProtectHome=true
```

those symlinks could not be followed by the daemon.

This explains why the same files worked for elevated build-tree tests but appeared missing inside `fprintd`.

---

## 10. Correct system-visible Validity layout

The development symlinks were replaced with real root-owned files copied from the frozen `permanent-data` bundle.

Device files became:

```text
/usr/local/share/libfprint/validity/06cb_00b7/init.bin
/usr/local/share/libfprint/validity/06cb_00b7/db_write_enable.bin
```

with normal regular-file permissions:

```text
-rw-r--r-- root root ... init.bin
-rw-r--r-- root root ... db_write_enable.bin
```

The seven shared Validity files were likewise installed as real files under:

```text
/usr/local/share/libfprint/validity/
```

The clean installation method uses:

```bash
sudo install -m 0644 ...
```

rather than symlinks into a home directory.

---

## 11. MAJOR PHASE 2 MILESTONE: fprintd enrollment succeeds

After restarting `fprintd`, the command:

```bash
fprintd-enroll -f right-index-finger "$USER"
```

completed successfully.

Observed output:

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

This is decisive proof that Linux Mint's normal `fprintd` stack can now enroll fingerprints through the native Validity driver on this machine.

The sensor is therefore beyond experimental build-tree-only use: the system daemon itself is successfully driving enrollment.

---

## 12. Current system changes

Current reversible system integration includes:

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
fprintd correct/wrong verification        NEXT
PAM / sudo                                PENDING
Desktop login / lock screen               PENDING
Reboot persistence                        PENDING
Suspend/resume                            PENDING
Rollback documentation                    PENDING
```

---

## 14. Immediate next milestone

Before touching PAM, run `fprintd-verify` and prove both sides:

1. enrolled right index finger is accepted;
2. a different finger is rejected.

Only after that should fingerprint authentication be enabled for `sudo`, login, or lock-screen use.

---

## 15. Current project state in one sentence

> **The HP EliteBook 840 G6 `06cb:00b7` fingerprint reader is now proven not only at the native libfprint level but through Linux Mint's actual `fprintd` service: the daemon successfully loads the staged MR !626 library, sees the sensor, accesses the frozen Validity data as real system files, and completes full right-index enrollment; `fprintd-verify` is the next gate before PAM integration.**