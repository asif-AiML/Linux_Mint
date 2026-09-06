# FingerPrint Sensor — HP EliteBook 840 G6

This folder contains the complete working context for the built-in fingerprint reader on an HP EliteBook 840 G6 running Linux Mint.

## Current status

The sensor itself is **solved and proven working natively under Linux**, and Phase 2 system integration is now partially complete.

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
```

So this is no longer a hardware-support investigation. The active work is now **system authentication integration**.

---

## Files in this folder

### `Fingerprint_Reader_Setup_Guide.md`

Start here when setting up the reader on a fresh Linux Mint install.

It contains the refined, reproducible successful path. Phase 1 is complete and the currently proven part of Phase 2 is now documented there as well.

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
5. `fprintd-enroll` completes full right-index enrollment successfully.

Still to prove:

1. `fprintd-verify` correct finger;
2. `fprintd-verify` wrong finger rejection;
3. `sudo` authentication;
4. desktop login;
5. lock-screen unlock;
6. reboot persistence;
7. suspend/resume reliability;
8. clean rollback/uninstall path.

---

## Important rules for future work

- Do not restart reverse engineering from zero. The sensor and native driver are proven.
- Do not blindly use the newest upstream libfprint. The exact known-good commit is recorded above.
- Do not regenerate Validity blobs if the preserved files are present and pass SHA-256 verification.
- Do not run `ninja install` or overwrite Mint's system libfprint casually.
- The currently proven integration method stages libfprint under `/usr/local/lib/fprintd-validity/` and uses a systemd override.
- Do not use Validity symlinks that point into `/home/...` for `fprintd`; its service sandbox blocks them.
- Do not modify PAM until `fprintd-verify` is proven first.
- Keep all fingerprint-specific files inside this `FingerPrint_Sensor/` directory in the `Linux_Mint` repository.

---

## Guidance for AI assistants

If this repository is handed to an AI assistant:

1. Read this `README.md` for the current state.
2. Read `Fingerprint_Reader_Setup_Guide.md` for the reproducible successful path.
3. Read `Fingerprint_Reader_Path1_Progress.md` only when detailed debugging context is needed.
4. Treat Phase 1 as solved.
5. Treat the current Phase 2 checkpoint as: **`fprintd-enroll` works successfully.**
6. Continue with `fprintd-verify` before suggesting any PAM changes.
7. Treat the known-good libfprint commit and preserved Validity files as immutable fallback anchors.

The immediate engineering objective is to prove correct/wrong-finger verification through `fprintd`, then enable Linux Mint authentication features one by one with password fallback preserved.