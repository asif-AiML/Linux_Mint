# Fingerprint Login Greeter Optimization — Linux Mint / LightDM / slick-greeter

**Project:** Fingerprint reader system integration on Linux Mint  
**Machine:** HP EliteBook 840 G6  
**Sensor:** Synaptics `06cb:00b7`  
**OS:** Linux Mint 22.3 Zena  
**Display manager:** LightDM `1.30.0-0ubuntu14`  
**Greeter:** slick-greeter `2.2.6+zena`

---

## Why this path exists

The fingerprint reader already works through the native Linux authentication stack for `fprintd`, PAM, `sudo`, Cinnamon lock-screen unlock, and fresh-boot authentication.

The remaining UX issue is limited to the LightDM login greeter:

```text
touch fingerprint -> authentication succeeds -> press Enter / click Log In -> desktop
```

Desired behavior:

```text
touch fingerprint -> desktop
```

Because the current flow already works, this optimization is only worth keeping if it stays small, reversible, and close to upstream behavior.

---

## Decision rule

Proceed only with one of:

```text
supported configuration change
small reversible slick-greeter change
small upstream-backed patch
```

Stop if the solution requires:

```text
replacing LightDM
replacing slick-greeter with another greeter
fragile PAM hacks
large custom greeter maintenance
blindly overwriting packaged system files
```

---

## Active login stack

Installed packages:

```text
lightdm          1.30.0-0ubuntu14
lightdm-settings 2.1.1
slick-greeter    2.2.6+zena
```

Effective LightDM configuration includes:

```text
[Seat:*]
greeter-session=slick-greeter
user-session=cinnamon
```

The active greeter session definition is:

```text
/usr/share/xgreeters/slick-greeter.desktop
```

with:

```ini
[Desktop Entry]
Name=Slick Greeter
Comment=Slick Greeter
Exec=slick-greeter
Type=Application
X-Ubuntu-Gettext-Domain=slick-greeter
```

No custom greeter override currently exists under `/etc/lightdm`.

---

## Configuration-only path — CLOSED

The installed schema:

```text
/usr/share/glib-2.0/schemas/x.dm.slick-greeter.gschema.xml
```

contains visual and UI settings such as backgrounds, themes, icons, fonts, HiDPI, keyboard, accessibility, clock, and monitor placement.

It contains no option for:

```text
fingerprint auto-submit
automatic session start after PAM success
login-button bypass
auto-login after fingerprint authentication
```

Therefore:

```text
config-only fix -> NOT AVAILABLE
```

---

## Exact upstream root cause

Upstream slick-greeter contains a fix for this exact behavior.

Commit:

```text
6902ed325ef358ed4cf3af0b7f04a0d078d18d4e
```

Title:

```text
Don't force authenticated user to press the Log In button
```

Date:

```text
2026-07-01
```

The old greeter logic relied on whether PAM had produced a normal prompt. `pam_fprintd` can instead present an informational PAM message, so fingerprint authentication may complete successfully even though slick-greeter does not consider a prompt to have happened. The greeter then stays authenticated but waits for Enter / Log In.

This exactly matches the observed behavior on Linux Mint 22.3.

---

## Exact upstream 2.2.6 baseline

The upstream repository exposes tag `2.2.6`:

```text
refs/tags/2.2.6      -> 04cf4987ac32ab8656c49787b08b8a5fa1cde78d
refs/tags/2.2.6^{}   -> d1f81b4406d5a756d2274c3dbbbd39bd1bd0f6d4
```

That source contains the old logic:

```vala
protected bool prompted = false;
```

and:

```vala
if (prompted && !unacknowledged_messages)
```

The old message callback also marks PAM messages as unacknowledged.

Therefore the source-level cause is confirmed for upstream `2.2.6`.

---

## Important correction about the installed Mint binary

An earlier check used:

```bash
strings /usr/sbin/slick-greeter | grep -F "Login immediately if PAM interacted"
```

and produced no output.

That phrase is a source-code comment, so its absence from a compiled binary is not evidence that the fix is absent.

Correct status:

```text
exact upstream 2.2.6 source lacks fix       CONFIRMED
Mint 2.2.6+zena exact packaged source       NOT YET PROVEN
installed binary fix membership             NOT CONCLUSIVELY DETERMINED
```

The observed Mint behavior remains consistent with the old logic, but the comment-string test is not used as proof.

---

## Local patch workspace

Workspace:

```text
~/fingerprint-path1/slick-greeter-2.2.6
```

Baseline commit:

```text
d1f81b4406d5a756d2274c3dbbbd39bd1bd0f6d4
```

Because the clone was shallow and pinned to the exact tag, the newer fix commit was fetched explicitly:

```bash
git fetch origin 6902ed325ef358ed4cf3af0b7f04a0d078d18d4e
```

Then cherry-picked:

```bash
git cherry-pick 6902ed325ef358ed4cf3af0b7f04a0d078d18d4e
```

Result:

```text
[detached HEAD 75d95a9] Don't force authenticated user to press the Log In button
3 files changed, 52 insertions(+), 10 deletions(-)
```

Most importantly:

```text
merge conflicts -> NONE
```

Local patched commit:

```text
75d95a9
```

This is strong evidence that the upstream fix is structurally compatible with exact `2.2.6`.

---

## Patched source verification — PASS

The patched source was checked directly:

```bash
grep -n "auth_interaction_seen" src/greeter-list.vala
```

Observed lines:

```text
790:    protected bool auth_interaction_seen = false;
805:            auth_interaction_seen = true;
821:        auth_interaction_seen = true;
856:            if (auth_interaction_seen && !unacknowledged_messages)
871:                auth_interaction_seen = true;
877:            if (auth_interaction_seen)
902:        auth_interaction_seen = false;
```

Therefore the intended upstream runtime logic is definitely present in the local patched source.

---

## Build dependencies and configuration

The source uses Meson and Vala/C.

Observed dependencies include:

```text
cairo
gdk-x11-3.0
gio-2.0
gio-unix-2.0
gtk+-3.0 >= 3.20.0
libcanberra
liblightdm-gobject-1 >= 1.12.0
pixman-1
x11
```

Additional development packages required during this experiment:

```text
valac
libcanberra-dev
liblightdm-gobject-1-dev
```

The existing project environment provides:

```text
Meson 1.12.0
Ninja 1.13.2
```

---

## First local build — SUCCESS

Initial Meson configuration and build completed successfully.

Compilation finished with warnings but no errors:

```text
Compilation succeeded - 60 warning(s)
[156/156] Linking target src/slick-greeter
```

The warnings were mainly existing GTK deprecations and Vala nullability warnings.

Produced executable:

```text
~/fingerprint-path1/slick-greeter-2.2.6/build/src/slick-greeter
```

Observed size during the build:

```text
1.9M
```

No system greeter was modified.

---

## Runtime dependency comparison — PASS

`ldd` was run against both:

```text
local patched build:
~/fingerprint-path1/slick-greeter-2.2.6/build/src/slick-greeter

Mint stock binary:
/usr/sbin/slick-greeter
```

Both resolve the same normal system runtime stack, including:

```text
libgtk-3.so.0
libgdk-3.so.0
libcairo.so.2
libcanberra.so.0
liblightdm-gobject-1.so.0
libX11.so.6
libpixman-1.so.0
GLib / GIO / Pango / ATK and related dependencies
```

No required library is missing.

No runtime dependency is being loaded from:

```text
~/fingerprint-path1
tools-venv
```

This is an important compatibility signal.

---

## ELF path inspection — PASS

The patched binary was inspected with:

```bash
readelf -d build/src/slick-greeter | grep -E 'RPATH|RUNPATH|NEEDED'
```

Result:

```text
NEEDED entries present normally
RPATH   absent
RUNPATH absent
```

Therefore the patched greeter is not tied to the build directory or virtual environment at runtime.

---

## Asset-path mismatch found and corrected

The first successful build used Meson's default prefix and embedded paths such as:

```text
/usr/local/share/slick-greeter
```

Mint's packaged greeter assets actually live under:

```text
/usr/share/slick-greeter
```

So the first build was intentionally rejected for staging.

The build directory was recreated with:

```bash
meson setup build --prefix=/usr
```

Meson confirmed:

```text
slick-greeter 2.2.6

User defined options
  prefix: /usr
```

After recompilation, embedded paths were checked again:

```bash
strings build/src/slick-greeter | grep -E '/usr/(local/)?share/slick-greeter'
```

All relevant paths now resolve to:

```text
/usr/share/slick-greeter
```

The incorrect `/usr/local/share/slick-greeter` paths are gone.

Therefore:

```text
Mint asset-layout compatibility -> PASS
```

---

## Stock package layout

`dpkg -L slick-greeter` confirms the Mint package owns:

```text
/usr/sbin/slick-greeter
/usr/share/slick-greeter/...
/usr/share/xgreeters/slick-greeter.desktop
```

The asset tree contains the greeter icons, backgrounds, session badges, and related resources.

This reinforces the decision to reuse Mint's existing `/usr/share/slick-greeter` assets rather than installing a duplicate asset tree.

---

## Stock binary rollback anchor

Before any activation, the current Mint binary was recorded:

```text
-rwxr-xr-x 1 root root 424168 Jan 8 2026 /usr/sbin/slick-greeter
```

SHA-256:

```text
583acf57cd2fdf15db0118649b03983f0ad24c4cbc9a6a8309610fe87667a1aa  /usr/sbin/slick-greeter
```

This is now the known stock-binary anchor for the current installed package state.

The stock binary has **not** been overwritten.

---

## Preferred activation architecture

Direct replacement of:

```text
/usr/sbin/slick-greeter
```

is explicitly avoided.

The preferred direction is to stage the patched executable separately, for example conceptually under:

```text
/usr/local/libexec/slick-greeter-fingerprint
```

and provide a separate greeter session entry, for example:

```text
/usr/share/xgreeters/slick-greeter-fingerprint.desktop
```

whose `Exec=` points explicitly to the staged patched binary.

LightDM can then select that separate greeter through a small `/etc/lightdm/...` override.

This would preserve the stock Mint package untouched and make rollback conceptually simple:

```text
disable/remove custom LightDM greeter override
-> LightDM returns to stock slick-greeter
```

This architecture is not yet activated. It is the current preferred design pending final rollback verification.

---

## Current assessment

```text
Observed extra Enter/click requirement      CONFIRMED
Active greeter                              slick-greeter 2.2.6+zena
Config-only option                          NOT AVAILABLE
Exact upstream fix                          IDENTIFIED
Upstream fix commit                         6902ed325ef358ed4cf3af0b7f04a0d078d18d4e
Exact upstream 2.2.6 baseline               CONFIRMED
2.2.6 baseline commit                       d1f81b4406d5a756d2274c3dbbbd39bd1bd0f6d4
Source-level old behavior                   CONFIRMED
Installed Mint packaged source match        NOT YET PROVEN
Clean backport onto 2.2.6                   PASS
Patched local commit                        75d95a9
Patched source logic present                PASS
Meson configure                             PASS
Local compile                               PASS
Runtime library resolution                  PASS
Missing shared libraries                    NONE
RPATH / RUNPATH                             NONE
Mint asset prefix                           PASS
Stock greeter preserved                     YES
Stock binary SHA-256                        RECORDED
Reversible isolated activation              PLANNED
Automatic fingerprint -> desktop login      PENDING
```

---

## Safety rules for the remaining work

- Do not run `ninja install`.
- Do not overwrite `/usr/sbin/slick-greeter`.
- Do not remove the stock xgreeter desktop entry.
- Do not change PAM for this greeter optimization.
- Design rollback before selecting the patched greeter.
- Rollback must be possible from a TTY even if the graphical greeter fails.
- Test both fingerprint and password paths after activation.
- If the maintenance cost becomes disproportionate to removing one Enter press, stop and keep the current working flow.

---

## Required tests after reversible activation

If the isolated greeter path is activated, test in this order:

```text
1. greeter starts normally
2. correct fingerprint -> desktop automatically
3. wrong fingerprint -> normal failure / password fallback
4. normal password login still works
5. reboot persistence
6. rollback to stock greeter
```

Only keep the optimization if all tests pass.

---

## Future Linux Mint major-upgrade workflow — RESERVED

After a future Mint upgrade, especially beyond Zena:

```text
check installed slick-greeter version
check whether Mint now ships the upstream fix
verify actual fingerprint login behavior
remove the local patched greeter if distro behavior is fixed
only rebuild/reapply if the fix is still absent and compatibility is confirmed
```

The final setup guide should eventually include this upgrade workflow so a local workaround is never carried forward unnecessarily.

---

## Current path in one sentence

> The exact upstream fingerprint-login fix cleanly backports onto slick-greeter 2.2.6, the patched source and binary now pass local build, linkage, ELF-path, and Mint asset-layout checks, the stock Mint greeter remains untouched with its SHA-256 recorded, and the next task is to design a TTY-safe reversible LightDM switch to an isolated patched greeter before performing the first real login test.
