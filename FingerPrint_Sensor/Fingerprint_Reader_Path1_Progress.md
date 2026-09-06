# Fingerprint Reader on HP EliteBook 840 G6 — Native Linux Investigation Log

**Project:** Native Linux fingerprint support on Linux Mint  
**Machine:** HP EliteBook 840 G6  
**Sensor:** Synaptics `06cb:00b7` — Fingerprint reader [HP G6]  
**OS:** Linux Mint 22.3 (Zena), Ubuntu Noble base  
**Kernel during testing:** `7.0.0-30-generic`  
**Known-good driver:** libfprint MR !626 at `0fd78560a245eebec1c93e71ee1f29b15ec1be67`  
**Current state:** Native libfprint, `fprintd`, and PAM-backed `sudo` authentication are now proven working. Correct fingerprint authenticates; a wrong fingerprint falls back safely to password.

---

## Proven hardware/driver baseline

```text
USB ID                  06cb:00b7
Sensor                  57K0 FM-3439-001
Sensor type             0x0d51
Native enrollment       PASS
Native correct verify   MATCH
Native wrong verify     NO MATCH
```

Required Validity data is preserved under:

```text
FingerPrint_Sensor/permanent-data/validity/
```

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

---

## Phase 2 — fprintd integration

Mint uses:

```text
/usr/libexec/fprintd
/usr/lib/systemd/system/fprintd.service
```

The known-good MR !626 library was staged under:

```text
/usr/local/lib/fprintd-validity/
```

and loaded through the reversible systemd drop-in:

```text
/etc/systemd/system/fprintd.service.d/validity.conf
```

with:

```ini
[Service]
Environment=LD_LIBRARY_PATH=/usr/local/lib/fprintd-validity
```

The distro libfprint was not overwritten and `ninja install` was never run.

Because `fprintd.service` has `ProtectHome=true`, the Validity files had to be real system files under `/usr/local/share/libfprint/validity/`; symlinks into `/home/...` failed.

### fprintd proof

```text
fprintd device detection           PASS
fprintd enrollment                 PASS
correct finger                     verify-match
wrong finger                       verify-no-match
```

---

## PAM integration

Mint's packaged PAM profile is:

```text
/usr/share/pam-configs/fprintd
```

with:

```text
Name: Fingerprint authentication
Default: no
Priority: 260
Auth-Type: Primary
Auth:
    [success=end default=ignore] pam_fprintd.so max-tries=1 timeout=10
```

Fingerprint authentication was enabled using:

```bash
sudo pam-auth-update
```

Only **Fingerprint authentication** was enabled; the separate Fingwit profile was left disabled.

After activation, `/etc/pam.d/common-auth` contained:

```text
auth [success=2 default=ignore] pam_fprintd.so max-tries=1 timeout=10
auth [success=1 default=ignore] pam_unix.so nullok try_first_pass
```

This preserves password fallback.

---

## MAJOR MILESTONE: sudo fingerprint authentication works

A fresh sudo authentication was forced with:

```bash
sudo -k
sudo true
```

The prompt displayed:

```text
Place your right index finger on the fingerprint reader
```

Touching the enrolled right index finger authenticated successfully and the command completed.

A second test deliberately used a wrong finger. The fingerprint attempt failed and PAM correctly continued to the normal password prompt. Entering the password authenticated successfully.

Therefore both paths are proven:

```text
correct fingerprint  -> sudo authentication succeeds
wrong fingerprint    -> password fallback remains available
```

This is the desired safe daily-use behavior.

---

## Current proof matrix

```text
Physical sensor detection                 PASS
Native driver open                        PASS
TLS/session                               PASS
Calibration                               PASS
Native enrollment                         PASS
Native correct-finger verify              PASS
Native wrong-finger rejection             PASS
fprintd loads staged MR !626 library      PASS
fprintd detects 06cb:00b7                 PASS
fprintd enrollment                        PASS
fprintd correct-finger verification       PASS
fprintd wrong-finger rejection            PASS
PAM fingerprint profile enabled           PASS
sudo correct-finger authentication        PASS
sudo wrong-finger password fallback       PASS
Desktop login                             NEXT
Lock-screen unlock                        NEXT
Reboot persistence                        PENDING
Suspend/resume                            PENDING
Rollback documentation                    PENDING
```

---

## Current reversible system changes

```text
/usr/local/lib/fprintd-validity/
/etc/systemd/system/fprintd.service.d/validity.conf
/usr/local/share/libfprint/validity/...
PAM profile enabled through pam-auth-update
```

Password authentication remains enabled.

---

## Immediate next milestone

Test the desktop authentication path carefully, starting with the lock screen before relying on fingerprint for a fresh boot login. Keep password fallback available throughout testing.

---

## Current project state in one sentence

> **The HP EliteBook 840 G6 `06cb:00b7` fingerprint reader now works through Linux Mint's native authentication stack: MR !626 drives the sensor, fprintd enrolls and verifies correctly, and PAM-backed sudo authentication accepts the enrolled right index finger while safely falling back to the normal password after a failed fingerprint attempt.**
