# FingerPrint Sensor — HP EliteBook 840 G6

This folder contains the complete working context for the built-in fingerprint reader on an HP EliteBook 840 G6 running Linux Mint.

## Current status

The sensor itself is **solved and proven working natively under Linux**, and Phase 2 system integration is now well underway.

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
fprintd right-index enrollment           PASS
fprintd correct-finger verification      PASS
fprintd wrong-finger rejection           PASS
PAM fingerprint profile enabled          PASS
sudo fingerprint authentication          PASS
```

So this is no longer a hardware-support investigation. The active work is now **finishing daily system authentication integration and reliability testing**.

---

## Files in this folder

### `Fingerprint_Reader_Setup_Guide.md`

Start here when setting up the reader on a fresh Linux Mint install.

It contains the refined, reproducible successful path. Phase 1 is complete and the proven part of Phase 2 is documented there as the integration advances.

### `Fingerprint_Reader_Path1_Progress.md`

Detailed engineering/investigation log.

Use this for troubleshooting, understanding why specific files/settings are required, and seeing the reasoning behind the current system integration.

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

**IN PROGRESS.**

Already proven:

1. the known-good libfprint can be staged under `/usr/local/lib/fprintd-validity/` without replacing Mint's distro library;
2. a systemd drop-in can make `/usr/libexec/fprintd` load that staged library;
3. `fprintd-list` detects the Validity sensor;
4. the Validity files must be real system files rather than symlinks into `/home` because `fprintd.service` uses `ProtectHome=true`;
5. `fprintd-enroll` completes full right-index enrollment successfully;
6. `fprintd-verify` accepts the enrolled right index and rejects a different finger;
7. Mint's packaged `Fingerprint authentication` PAM profile can be enabled with `pam-auth-update` while keeping password authentication enabled;
8. `sudo -k && sudo true` prompts for the right index finger and succeeds immediately after a correct touch.

Still to prove:

1. password fallback behavior after a failed fingerprint attempt;
2. desktop login;
3. lock-screen unlock;
4. reboot persistence;
5. suspend/resume reliability;
6. clean rollback/uninstall path.

---

## Important rules for future work

- Do not restart reverse engineering from zero. The sensor and native driver are proven.
- Do not blindly use the newest upstream libfprint. The exact known-good commit is recorded above.
- Do not regenerate Validity blobs if the preserved files are present and pass SHA-256 verification.
- Do not run `ninja install` or overwrite Mint's system libfprint casually.
- The currently proven integration method stages libfprint under `/usr/local/lib/fprintd-validity/` and uses a systemd override.
- Do not use Validity symlinks that point into `/home/...` for `fprintd`; its service sandbox blocks them.
- Keep password authentication enabled as fallback while testing login and lock-screen integration.
- Keep all fingerprint-specific files inside this `FingerPrint_Sensor/` directory in the `Linux_Mint` repository.

---

## Guidance for AI assistants

If this repository is handed to an AI assistant:

1. Read this `README.md` for the current state.
2. Read `Fingerprint_Reader_Setup_Guide.md` for the reproducible successful path.
3. Read `Fingerprint_Reader_Path1_Progress.md` only when detailed debugging context is needed.
4. Treat Phase 1 as solved.
5. Treat `fprintd` enrollment and correct/wrong verification as solved.
6. Treat PAM-backed `sudo` fingerprint authentication as proven working.
7. Continue with password-fallback validation, then desktop login and lock-screen testing one step at a time.
8. Treat the known-good libfprint commit and preserved Validity files as immutable fallback anchors.

The immediate engineering objective is to validate password fallback after a failed fingerprint attempt before moving on to graphical login and lock-screen authentication.