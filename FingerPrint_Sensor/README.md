# FingerPrint Sensor — HP EliteBook 840 G6

This folder contains the complete working context for the built-in fingerprint reader on an HP EliteBook 840 G6 running Linux Mint.

## Current status

The sensor itself is **solved and proven working natively under Linux**.

Hardware:

```text
USB ID:     06cb:00b7
Sensor:     Synaptics / Validity 57K0 FM-3439-001
Sensor type: 0x0d51
```

Known-good native libfprint source:

```text
libfprint MR !626
commit 0fd78560a245eebec1c93e71ee1f29b15ec1be67
```

The following have all been proven on the physical machine:

```text
device detection                 PASS
driver open                      PASS
firmware communication           PASS
TLS/session establishment        PASS
sensor identification            PASS
calibration                      PASS
real fingerprint capture         PASS
full fingerprint enrollment      PASS
correct enrolled finger          MATCH
wrong finger                     NO MATCH
```

Therefore, this is no longer a hardware-support investigation. The remaining work is **system integration**.

---

## Files in this folder

### `Fingerprint_Reader_Setup_Guide.md`

Start here when setting up the reader on a fresh Linux Mint install.

It contains only the refined known-good procedure and is intended to be executable step by step by a beginner.

### `Fingerprint_Reader_Path1_Progress.md`

Detailed engineering/investigation log.

Use this when troubleshooting, reviewing why particular files are needed, or understanding previous blockers and decisions.

### `permanent-data/validity/`

This is the intended location for the frozen known-good Validity binary data used by the sensor.

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

These files should be verified with `SHA256SUMS` before use.

---

## Project phases

### Phase 1 — Native driver proof

**COMPLETE.**

The native driver can enroll and verify fingerprints correctly.

### Phase 2 — Daily system integration

**PENDING.**

Still to be proven and documented:

1. safe permanent libfprint installation/integration;
2. normal non-root USB permissions;
3. `fprintd-enroll` and `fprintd-verify`;
4. `sudo` authentication;
5. desktop login;
6. lock-screen unlock;
7. reboot persistence;
8. suspend/resume reliability;
9. clean rollback/uninstall path.

---

## Important rules for future work

- Do not restart reverse engineering from zero. The sensor and driver are already proven.
- Do not blindly use the newest upstream libfprint. The exact known-good commit is recorded above.
- Do not regenerate Validity blobs if the preserved known-good files are present and pass SHA-256 verification.
- Do not run `ninja install` or replace the system libfprint casually.
- Do not modify PAM until `fprintd` integration is proven first.
- Keep all fingerprint-specific files inside this `FingerPrint_Sensor/` directory in the `Linux_Mint` repository.

---

## Guidance for AI assistants

If this repository is handed to an AI assistant, use this order:

1. Read this `README.md` for the current state.
2. Read `Fingerprint_Reader_Setup_Guide.md` for the reproducible successful path.
3. Read `Fingerprint_Reader_Path1_Progress.md` only when detailed debugging history is needed.
4. Treat the known-good libfprint commit and preserved Validity files as immutable fallback anchors.
5. Continue from Phase 2 unless the user explicitly asks to revisit Phase 1.

The immediate engineering objective is to make the already-working native reader available safely through Linux Mint's normal `fprintd`/PAM authentication stack.