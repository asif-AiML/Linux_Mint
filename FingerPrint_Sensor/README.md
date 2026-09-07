# FingerPrint Sensor — HP EliteBook 840 G6

This folder contains the complete working context for the built-in fingerprint reader on an HP EliteBook 840 G6 running Linux Mint.

## Current status

The sensor itself is **solved and proven working natively under Linux**, and system-wide authentication is now working.

Hardware:

```text
USB ID:      06cb:00b7
Sensor:      Synaptics / Validity 57K0 FM-3439-001
Sensor type: 0x0d51
```

Known-good native libfprint source:

```text
libfprint MR !626
commit 0fd78560a245eebec1c93e71ee1f29b15ec1be67
```

Proven on the physical machine:

```text
device detection                         PASS
driver open                              PASS
firmware communication                   PASS
TLS/session establishment                PASS
sensor identification                    PASS
calibration                              PASS
real fingerprint capture                 PASS
native fingerprint enrollment            PASS
native correct enrolled finger           MATCH
native wrong finger                      NO MATCH
fprintd loads staged MR !626 libfprint   PASS
fprintd detects 06cb:00b7                PASS
fprintd enrollment                       PASS
fprintd correct-finger verification      PASS
fprintd wrong-finger rejection           PASS
PAM fingerprint profile enabled          PASS
sudo fingerprint authentication          PASS
sudo password fallback                   PASS
Cinnamon lock-screen fingerprint unlock  PASS
lock-screen password fallback            PASS
fresh-boot fingerprint authentication    PASS
reboot persistence                       PASS
```

Current cold-boot workflow:

```text
touch fingerprint -> press Enter -> desktop
```

The remaining work is optional UX optimization: removing the final Enter/Log In confirmation in LightDM/slick-greeter without weakening fallback behavior or replacing Mint's stock greeter.

---

## Files in this folder

### `Fingerprint_Reader_Setup_Guide.md`

Start here when setting up the reader on a fresh Linux Mint install.

It contains the refined reproducible successful path and will become the final clean-install guide once the remaining reliability/cleanup work is finished.

### `Fingerprint_Reader_Path1_Progress.md`

Detailed engineering/investigation log.

Use this for troubleshooting, exact proof milestones, greeter-backport work, and understanding why specific files/settings are required.

### `Fingerprint_Login_Greeter_Optimization.md`

Dedicated LightDM/slick-greeter UX investigation.

It documents the extra Enter/Log In behavior, upstream root cause, exact upstream fix, clean backport to slick-greeter 2.2.6, and the reversible staging strategy under development.

### `permanent-data/validity/`

Frozen known-good Validity data used by this sensor.

Expected layout:

```text
permanent-data/validity/
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

Verify these with `SHA256SUMS` before use.

---

## Project phases

### Phase 1 — Native driver proof

**COMPLETE.**

The native driver can enroll and verify fingerprints correctly.

### Phase 2 — Daily system integration

**FUNCTIONALLY WORKING.**

Proven:

1. known-good libfprint is staged under `/usr/local/lib/fprintd-validity/` without replacing Mint's distro library;
2. a systemd drop-in makes `/usr/libexec/fprintd` load the staged library;
3. required Validity files are installed as real system files because `fprintd.service` uses `ProtectHome=true`;
4. `fprintd-enroll` and correct/wrong `fprintd-verify` work;
5. Mint's PAM fingerprint profile works with password fallback;
6. `sudo` works with fingerprint and falls back to password after a failed fingerprint;
7. Cinnamon lock-screen fingerprint unlock works with password fallback;
8. fresh-boot fingerprint authentication works;
9. the complete stack survives reboot.

Still pending:

1. suspend/resume reliability;
2. final ownership/cleanup checks;
3. complete rollback/uninstall documentation.

### Optional greeter UX optimization

**IN PROGRESS.**

Upstream slick-greeter commit:

```text
6902ed325ef358ed4cf3af0b7f04a0d078d18d4e
Don't force authenticated user to press the Log In button
```

matches the observed fingerprint behavior.

The fix:

```text
cleanly cherry-picks onto exact upstream 2.2.6   PASS
patched source verification                     PASS
Meson configure                                 PASS
local compilation                               PASS
runtime library compatibility                   PASS
no RPATH/RUNPATH                                PASS
Mint /usr asset prefix rebuild                  PASS
```

The active system greeter has **not** been replaced.

Stock rollback/reference anchor:

```text
/usr/sbin/slick-greeter
SHA256: 583acf57cd2fdf15db0118649b03983f0ad24c4cbc9a6a8309610fe87667a1aa
```

The preferred direction is a separately staged patched greeter selected by a reversible LightDM configuration override rather than overwriting `/usr/sbin/slick-greeter`.

---

## Important rules for future work

- Do not restart reverse engineering from zero. The sensor and native driver are proven.
- Do not blindly use the newest upstream libfprint. The exact known-good commit is recorded above.
- Do not regenerate Validity blobs if the preserved files are present and pass SHA-256 verification.
- Do not run `ninja install` or casually overwrite Mint's system libfprint or greeter.
- Keep password authentication enabled as fallback.
- Do not copy raw diagnostic logs containing TLS/session material into the repository.
- Do not commit biometric template data such as `/var/lib/fprint` or `test-storage.variant`.
- For greeter work, prefer a tiny reversible upstream-backed staging/config change; stop if it grows into custom greeter maintenance or fragile PAM hacks.

---

## Guidance for AI assistants

If this repository is handed to an AI assistant:

1. Read this `README.md` for the current state.
2. Read `Fingerprint_Reader_Setup_Guide.md` for the reproducible successful setup path.
3. Read `Fingerprint_Reader_Path1_Progress.md` for detailed engineering history and current checkpoints.
4. Read `Fingerprint_Login_Greeter_Optimization.md` before changing anything related to LightDM/slick-greeter.
5. Treat native support, fprintd enrollment/verification, PAM, sudo, lock screen, password fallback and reboot persistence as solved.
6. Treat the known-good libfprint commit and preserved Validity files as immutable fallback anchors.
7. Do not overwrite the stock greeter during the current optimization path.
8. Continue in small testable steps, with rollback designed before activation.

The immediate engineering objective is to finish a reversible LightDM greeter staging plan, then test suspend/resume and complete final cleanup/rollback documentation.
