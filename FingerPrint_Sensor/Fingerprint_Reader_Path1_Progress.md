# Fingerprint Reader on HP EliteBook 840 G6 — Native Linux Investigation Log

**Project:** Native Linux fingerprint support on Linux Mint  
**Machine:** HP EliteBook 840 G6  
**Sensor:** Synaptics `06cb:00b7` — Fingerprint reader [HP G6]  
**OS:** Linux Mint 22.3 (Zena), Ubuntu Noble base  
**Kernel during testing:** `7.0.0-30-generic`  
**Known-good driver:** libfprint MR !626 at `0fd78560a245eebec1c93e71ee1f29b15ec1be67`  
**Current state:** Native libfprint, `fprintd`, PAM-backed `sudo`, lock-screen unlock, reboot persistence, and cold-boot fingerprint authentication all work. The remaining work is an optional LightDM/slick-greeter UX optimization so a successful fingerprint can enter the desktop without the extra Enter/Log In confirmation.

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

Fingerprint authentication was enabled using:

```bash
sudo pam-auth-update
```

Only **Fingerprint authentication** was enabled; the separate Fingwit profile was left disabled.

Password fallback remains enabled and was tested successfully.

---

## sudo and lock-screen authentication

Proven behavior:

```text
correct fingerprint -> sudo succeeds
wrong fingerprint   -> password fallback works
correct fingerprint -> Cinnamon lock screen unlocks
wrong fingerprint   -> lock-screen password fallback works
```

Lock-screen UX note: the unlock UI must first be woken with keyboard/mouse input. The fingerprint sensor itself is not used as a wake event.

---

## Reboot persistence and fresh-boot login

A full reboot confirmed persistence of the system-wide fingerprint stack:

```text
systemd drop-in persists                 PASS
staged libfprint still loads             PASS
Validity data remains accessible         PASS
enrolled fingerprint persists            PASS
PAM fingerprint authentication persists  PASS
fresh-boot fingerprint prompt appears    PASS
```

At the LightDM/slick-greeter login screen, the enrolled fingerprint authenticates successfully.

The important UX detail was refined during testing: a mouse click on **Log In** is not required specifically; pressing **Enter** also confirms the already-authenticated login.

Current cold-boot flow:

```text
touch enrolled fingerprint -> press Enter -> desktop
```

Previous PIN flow:

```text
type 4-digit PIN -> press Enter -> desktop
```

So cold-boot fingerprint authentication itself is fully working. The remaining issue is only the extra final confirmation after successful PAM authentication.

---

## LightDM / slick-greeter optimization investigation

Active greeter package:

```text
slick-greeter 2.2.6+zena
```

The installed GSettings schema exposes visual/UI configuration only and has no option for fingerprint auto-submit or automatic session start after PAM success.

Upstream contains an exact fix for this behavior:

```text
commit: 6902ed325ef358ed4cf3af0b7f04a0d078d18d4e
title:  Don't force authenticated user to press the Log In button
date:   2026-07-01
```

The exact upstream `2.2.6` tag points to:

```text
d1f81b4406d5a756d2274c3dbbbd39bd1bd0f6d4
```

That source contains the old `prompted`-based authentication logic. The upstream fix changes the logic to track broader PAM interaction with `auth_interaction_seen`, which covers `pam_fprintd` informational messages.

The fix was fetched and cherry-picked cleanly onto exact upstream `2.2.6`:

```text
local patched commit: 75d95a9
merge conflicts:      NONE
```

Patched source verification:

```text
auth_interaction_seen declaration     PRESENT
message/prompt tracking               PRESENT
auth-complete condition               PRESENT
state reset logic                     PRESENT
```

The patched tree configured and compiled successfully with Meson/Ninja.

Build result:

```text
Compilation succeeded - 60 warning(s)
[156/156] Linking target src/slick-greeter
```

The warnings were non-fatal existing-code deprecation/nullability warnings.

### Runtime compatibility checks

The patched binary and Mint's stock `/usr/sbin/slick-greeter` resolve the same normal system shared-library set, including GTK3, GDK, Cairo, `libcanberra`, `liblightdm-gobject-1`, GLib/GIO, X11 and Pixman.

No missing shared libraries were found.

The patched binary has no `RPATH` or `RUNPATH`, so it does not depend on the local build tree or Python virtual environment at runtime.

An initial build used Meson's default `/usr/local` prefix and therefore embedded `/usr/local/share/slick-greeter` asset paths. That build was deliberately rejected for staging.

The tree was rebuilt correctly with:

```bash
meson setup build --prefix=/usr
ninja -C build
```

After rebuild, all relevant embedded asset paths point to Mint's real asset location:

```text
/usr/share/slick-greeter
```

### Stock greeter anchor

Current installed stock binary:

```text
-rwxr-xr-x 1 root root 424168 Jan  8  2026 /usr/sbin/slick-greeter
```

SHA-256:

```text
583acf57cd2fdf15db0118649b03983f0ad24c4cbc9a6a8309610fe87667a1aa  /usr/sbin/slick-greeter
```

This hash is recorded as a rollback/reference anchor before any activation experiment.

The stock package also owns `/usr/share/slick-greeter/` assets and `/usr/share/xgreeters/slick-greeter.desktop`, whose launcher is simply:

```text
Exec=slick-greeter
```

The preferred implementation direction is therefore to avoid overwriting `/usr/sbin/slick-greeter`; instead, stage the patched executable separately and select it through a separate greeter-session definition/config override if the final LightDM behavior permits it.

---

## Important binary-verification correction

An earlier test searched the installed binary with `strings` for a source-code comment from the upstream fix. That was not a valid proof because source comments are normally discarded during compilation.

Correct status:

```text
exact upstream 2.2.6 source lacks fix      CONFIRMED
Mint 2.2.6+zena packaged source match      NOT YET PROVEN
installed binary fix presence              NOT CONCLUSIVELY DETERMINED
observed behavior matches old logic         YES
```

---

## Current proof matrix

```text
Physical sensor detection                 PASS
Native driver open                        PASS
TLS/session                               PASS
Calibration                              PASS
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
Lock-screen fingerprint unlock            PASS
Lock-screen password fallback             PASS
Fresh-boot fingerprint authentication     PASS
Reboot persistence                        PASS
Greeter source root cause                 CONFIRMED
Exact upstream greeter fix                CONFIRMED
2.2.6 clean cherry-pick                   PASS
Patched greeter local configure           PASS
Patched greeter local build               PASS
Patched runtime dependency check           PASS
Patched asset-prefix check                 PASS
Stock greeter rollback hash recorded       PASS
Fresh-boot auto-enter desktop              PENDING
Suspend/resume                            PENDING
Final rollback documentation              PENDING
```

---

## Current reversible system changes

```text
/usr/local/lib/fprintd-validity/
/etc/systemd/system/fprintd.service.d/validity.conf
/usr/local/share/libfprint/validity/...
PAM profile enabled through pam-auth-update
```

The greeter optimization path has not yet modified the active system greeter.

---

## Immediate next direction

The fingerprint stack itself is proven for daily authentication.

The optional greeter path now has a locally built, source-verified, runtime-compatible candidate. Before activation, the next requirement is to design a reversible staging method that leaves Mint's stock `/usr/sbin/slick-greeter` untouched and can be rolled back from a TTY if the graphical greeter fails.

After the greeter path is resolved or intentionally stopped, remaining reliability work is suspend/resume testing plus final cleanup/rollback documentation.

---

## Current project state in one sentence

> **The HP EliteBook 840 G6 `06cb:00b7` fingerprint reader is fully working through Linux Mint's native authentication stack for fprintd, sudo, lock-screen unlock and fresh-boot authentication with password fallback and reboot persistence; the remaining optional UX work is a carefully staged upstream slick-greeter backport so successful boot-time fingerprint authentication can transition directly to the desktop without the final Enter key, while keeping the stock greeter untouched and rollback-safe.**
