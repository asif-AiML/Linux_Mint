# FingerPrint Sensor — HP EliteBook 840 G6

This folder contains the complete working context for the built-in fingerprint reader on an HP EliteBook 840 G6 running Linux Mint.

## Current status

The sensor itself is **solved and proven working natively under Linux**, system-wide authentication is working, and the LightDM login flow has now been successfully optimized.

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
LightDM fingerprint auto-login           PASS
```

Final cold-boot workflow:

```text
touch fingerprint -> desktop
```

No Enter press and no Log In click are required after successful fingerprint authentication.

---

## Fresh-install hierarchy

For a new Linux Mint installation, follow the guides in this order:

```text
1. Fingerprint_Reader_Setup_Guide.md
        ↓
2. Fingerprint_Login_Greeter_Fresh_Install_Guide.md
```

### Stage 1 — Fingerprint stack

`Fingerprint_Reader_Setup_Guide.md` establishes the main fingerprint environment and system integration.

It creates and uses the project workspace, including:

```text
~/fingerprint-path1/
~/fingerprint-path1/tools-venv/
~/fingerprint-path1/permanent-data/validity/
```

The preserved `permanent-data/validity/` files are used during the native sensor/libfprint setup, and the same project workspace can then be reused for the greeter build stage.

The expected result after Stage 1 is:

```text
sensor works
fprintd works
PAM works
sudo works
Cinnamon lock screen works
fresh-boot fingerprint authentication works
password fallback remains available
```

At this point the stock Mint greeter may still require:

```text
touch fingerprint -> press Enter / click Log In -> desktop
```

### Stage 2 — LightDM greeter optimization

`Fingerprint_Login_Greeter_Fresh_Install_Guide.md` starts from the already-working fingerprint stack and applies the successful slick-greeter optimization.

It reuses the existing workspace where useful, especially the Meson/Ninja environment, then:

```text
checks out exact slick-greeter 2.2.6
applies the exact upstream fingerprint-login fix
builds with --prefix=/usr
stages the patched greeter separately
creates a separate xgreeter desktop entry
selects it through a reversible LightDM override
```

The expected final result is:

```text
touch fingerprint -> desktop
```

This two-guide sequence is the recommended clean-install route.

---

## Files in this folder

### `Fingerprint_Reader_Setup_Guide.md`

**Fresh-install guide — Stage 1. Start here.**

It contains the refined reproducible path for native sensor support, preserved Validity data, libfprint/fprintd integration, PAM, sudo, lock screen, password fallback, and fresh-boot authentication.

### `Fingerprint_Login_Greeter_Fresh_Install_Guide.md`

**Fresh-install guide — Stage 2. Run after `Fingerprint_Reader_Setup_Guide.md`.**

It contains the direct successful LightDM/slick-greeter path that removes the final Enter/Log In action while keeping the Mint stock greeter untouched and rollback available.

### `Fingerprint_Reader_Path1_Progress.md`

Detailed native-driver/system-integration engineering log.

Use this for troubleshooting, exact proof milestones, historical investigation, and understanding why the Validity files and libfprint choices are required.

### `Fingerprint_Login_Greeter_Optimization.md`

Detailed LightDM/slick-greeter investigation and technical history.

It documents the original extra Enter/Log In behavior, upstream root cause, exact upstream fix, clean backport to slick-greeter 2.2.6, build validation, the first invalid activation attempt, reversible staging design, and the final successful auto-login result.

This is a reference/troubleshooting document, not the preferred fresh-install path.

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

These preserved files are hardware-specific and should remain in this repository. The slick-greeter source tree or compiled greeter binary does **not** need to be preserved here because the successful greeter build is reproducible from exact upstream Git references documented in the fresh-install guide.

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

### LightDM greeter UX optimization

**SUCCESSFUL.**

Upstream slick-greeter repository:

```text
https://github.com/linuxmint/slick-greeter
```

Exact baseline:

```text
tag:    2.2.6
commit: d1f81b4406d5a756d2274c3dbbbd39bd1bd0f6d4
```

Exact upstream fix:

```text
6902ed325ef358ed4cf3af0b7f04a0d078d18d4e
Don't force authenticated user to press the Log In button
```

Validation:

```text
clean cherry-pick onto exact 2.2.6          PASS
patched source verification                 PASS
Meson configure                             PASS
local compilation                           PASS
runtime library compatibility               PASS
no RPATH/RUNPATH                            PASS
Mint /usr asset prefix rebuild              PASS
isolated patched binary staging             PASS
LightDM custom greeter selection            PASS
fingerprint -> automatic desktop login      PASS
```

The stock `/usr/sbin/slick-greeter` remains untouched.

Stock rollback/reference anchor:

```text
/usr/sbin/slick-greeter
SHA256: 583acf57cd2fdf15db0118649b03983f0ad24c4cbc9a6a8309610fe87667a1aa
```

Successful staged greeter path:

```text
/usr/local/libexec/slick-greeter-fingerprint
```

Custom greeter session:

```text
/usr/share/xgreeters/slick-greeter-fingerprint.desktop
```

LightDM selection override:

```text
/etc/lightdm/lightdm.conf.d/99-fingerprint-greeter.conf
```

Final behavior:

```text
touch fingerprint -> desktop
```

---

## Important rules for future work

- Do not restart reverse engineering from zero. The sensor and native driver are proven.
- Do not blindly use the newest upstream libfprint. The exact known-good commit is recorded above.
- Do not regenerate Validity blobs if the preserved files are present and pass SHA-256 verification.
- Do not run `ninja install` or casually overwrite Mint's system libfprint or greeter.
- Keep password authentication enabled as fallback.
- Do not copy raw diagnostic logs containing TLS/session material into the repository.
- Do not commit biometric template data such as `/var/lib/fprint` or `test-storage.variant`.
- Preserve `permanent-data/validity/` because it contains hardware-specific known-good data.
- Do not preserve the compiled slick-greeter binary as a long-term source of truth; rebuild it from the recorded upstream tag and fix commit when needed.
- After a major Mint upgrade, first check whether Mint now ships the upstream slick-greeter fix natively before rebuilding the custom greeter.

---

## Guidance for AI assistants

If this repository is handed to an AI assistant:

1. Read this `README.md` for the current state and document hierarchy.
2. For a fresh install, follow `Fingerprint_Reader_Setup_Guide.md` first.
3. Then follow `Fingerprint_Login_Greeter_Fresh_Install_Guide.md` for the successful LightDM optimization.
4. Use `Fingerprint_Reader_Path1_Progress.md` only when native-driver/system-integration history or troubleshooting is needed.
5. Use `Fingerprint_Login_Greeter_Optimization.md` only when greeter investigation history or troubleshooting is needed.
6. Treat native support, fprintd enrollment/verification, PAM, sudo, lock screen, password fallback, reboot persistence, and LightDM fingerprint auto-login as solved.
7. Treat the known-good libfprint commit and preserved Validity files as immutable fallback anchors.
8. Keep the stock Mint greeter untouched; use the documented isolated staged greeter approach.
9. Continue future work in small testable steps with rollback defined before activation.

The remaining engineering work is now mainly suspend/resume validation, final cleanup/ownership checks, and complete rollback/uninstall documentation.
