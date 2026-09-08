# Fingerprint Login Greeter Optimization — Linux Mint / LightDM / slick-greeter

**Project:** Fingerprint reader system integration on Linux Mint  
**Machine:** HP EliteBook 840 G6  
**Sensor:** Synaptics `06cb:00b7`  
**OS:** Linux Mint 22.3 Zena  
**Display manager:** LightDM `1.30.0-0ubuntu14`  
**Greeter:** slick-greeter `2.2.6+zena`

---

## Final result — SUCCESS

The login-screen optimization is now working.

Before the patch:

```text
touch fingerprint -> authentication succeeds -> press Enter / click Log In -> desktop
```

After the patched greeter was actually selected by LightDM:

```text
touch fingerprint -> desktop
```

No Enter key and no Log In click are required.

The stock Mint greeter binary remains untouched.

---

## Why this path existed

The fingerprint reader itself already worked through the native Linux authentication stack for `fprintd`, PAM, `sudo`, Cinnamon lock-screen unlock, fresh-boot authentication, password fallback, and reboot persistence.

The remaining problem was only the LightDM/slick-greeter UX at fresh boot. Fingerprint authentication succeeded, but slick-greeter still required a final confirmation action.

Because the original flow was already usable, this optimization was only accepted if it could remain small, reversible, and closely aligned with upstream behavior.

---

## Decision rule used

Allowed:

```text
supported configuration change
small reversible slick-greeter change
small upstream-backed patch
```

Rejected:

```text
replacing LightDM
replacing slick-greeter with another greeter
fragile PAM hacks
large custom greeter maintenance
blindly overwriting packaged system files
```

The final solution satisfies this rule.

---

## Active login stack

Installed packages:

```text
lightdm          1.30.0-0ubuntu14
lightdm-settings 2.1.1
slick-greeter    2.2.6+zena
```

Mint's stock greeter configuration comes from:

```text
/usr/share/lightdm/lightdm.conf.d/90-slick-greeter.conf
```

The stock greeter session definition is:

```text
/usr/share/xgreeters/slick-greeter.desktop
```

and normally launches:

```text
/usr/sbin/slick-greeter
```

---

## Configuration-only path — CLOSED

The installed schema:

```text
/usr/share/glib-2.0/schemas/x.dm.slick-greeter.gschema.xml
```

contains appearance and UI settings, but no option for:

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

Repository:

```text
https://github.com/linuxmint/slick-greeter
```

Relevant commit:

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

The old greeter logic relied on whether PAM had produced a normal prompt. `pam_fprintd` can instead present an informational PAM message. Fingerprint authentication could therefore complete successfully while slick-greeter still believed no suitable prompt interaction had occurred, leaving the user authenticated but waiting for Enter / Log In.

That matched the observed Linux Mint 22.3 behavior exactly.

---

## Exact 2.2.6 baseline

The exact upstream tag used was:

```text
2.2.6
```

Tag objects:

```text
refs/tags/2.2.6      -> 04cf4987ac32ab8656c49787b08b8a5fa1cde78d
refs/tags/2.2.6^{}   -> d1f81b4406d5a756d2274c3dbbbd39bd1bd0f6d4
```

The exact `2.2.6` source contains the old logic:

```vala
protected bool prompted = false;
```

and:

```vala
if (prompted && !unacknowledged_messages)
```

The upstream fix replaces this prompt-only concept with `auth_interaction_seen` and treats valid non-error PAM interaction as sufficient for automatic session start after successful authentication.

---

## Local patch workspace

Workspace used:

```text
~/fingerprint-path1/slick-greeter-2.2.6
```

The exact source was cloned with:

```bash
git clone --branch 2.2.6 --depth 1 https://github.com/linuxmint/slick-greeter.git slick-greeter-2.2.6
```

Because the clone was shallow, the newer fix commit was fetched explicitly:

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

There were no merge conflicts.

Local patched commit:

```text
75d95a9
```

---

## Patched source verification — PASS

The patched source was checked directly:

```bash
grep -n "auth_interaction_seen" src/greeter-list.vala
```

Observed lines included:

```text
790:    protected bool auth_interaction_seen = false;
805:            auth_interaction_seen = true;
821:        auth_interaction_seen = true;
856:            if (auth_interaction_seen && !unacknowledged_messages)
871:                auth_interaction_seen = true;
877:            if (auth_interaction_seen)
902:        auth_interaction_seen = false;
```

Therefore the intended upstream runtime logic was definitely present in the local patched source.

---

## Build dependencies

The build used Meson/Ninja and required the normal slick-greeter development dependencies.

Relevant packages installed during the experiment included:

```text
valac
libcanberra-dev
liblightdm-gobject-1-dev
```

The build also uses development headers for GTK3, GLib/GIO, Cairo, X11, Pixman and related components.

The project-local environment provided:

```text
Meson 1.12.0
Ninja 1.13.2
```

---

## Build — SUCCESS

The first build succeeded but used Meson's default `/usr/local` prefix. That embedded asset paths under:

```text
/usr/local/share/slick-greeter
```

Mint's packaged assets live under:

```text
/usr/share/slick-greeter
```

so that build was intentionally rejected.

The tree was rebuilt with the correct prefix:

```bash
rm -rf build
meson setup build --prefix=/usr
ninja -C build
```

Result:

```text
Compilation succeeded - 60 warning(s)
[156/156] Linking target src/slick-greeter
```

Produced executable:

```text
~/fingerprint-path1/slick-greeter-2.2.6/build/src/slick-greeter
```

Embedded asset paths were then verified to point to:

```text
/usr/share/slick-greeter
```

with no `/usr/local/share/slick-greeter` paths remaining.

---

## Runtime compatibility checks — PASS

`ldd` comparison between the patched build and stock `/usr/sbin/slick-greeter` showed the same normal system runtime stack.

No library was missing and no runtime dependency came from:

```text
~/fingerprint-path1
tools-venv
```

`readelf` also showed:

```text
RPATH   absent
RUNPATH absent
```

Therefore the patched binary is not tied to the build workspace or Python virtual environment.

---

## Stock rollback anchors

Stock binary:

```text
/usr/sbin/slick-greeter
```

Recorded stock state:

```text
-rwxr-xr-x 1 root root 424168 Jan 8 2026 /usr/sbin/slick-greeter
```

SHA-256:

```text
583acf57cd2fdf15db0118649b03983f0ad24c4cbc9a6a8309610fe87667a1aa  /usr/sbin/slick-greeter
```

APT also confirmed the exact Mint package remained available:

```text
Installed: 2.2.6+zena
Candidate: 2.2.6+zena
```

This provides a second recovery layer:

```bash
sudo apt install --reinstall slick-greeter
```

The stock binary was never overwritten by this project.

---

## Final isolated installation layout

Patched executable:

```text
/usr/local/libexec/slick-greeter-fingerprint
```

Observed ownership/mode:

```text
-rwxr-xr-x root root /usr/local/libexec/slick-greeter-fingerprint
```

Custom greeter session definition:

```text
/usr/share/xgreeters/slick-greeter-fingerprint.desktop
```

Contents:

```ini
[Desktop Entry]
Name=Slick Greeter Fingerprint
Comment=Slick Greeter with fingerprint auto-login fix
Exec=/usr/local/libexec/slick-greeter-fingerprint
Type=Application
X-Ubuntu-Gettext-Domain=slick-greeter
```

LightDM override:

```text
/etc/lightdm/lightdm.conf.d/99-fingerprint-greeter.conf
```

Contents:

```ini
[Seat:*]
greeter-session=slick-greeter-fingerprint
```

`lightdm --show-config` correctly resolved:

```text
H  greeter-session=slick-greeter-fingerprint
```

from:

```text
H  /etc/lightdm/lightdm.conf.d/99-fingerprint-greeter.conf
```

---

## Important failed first activation — procedural error, not patch failure

The first reboot appeared negative because the login flow remained unchanged.

LightDM logs showed it still launched:

```text
/usr/sbin/slick-greeter
```

Later inspection found:

```text
/etc/lightdm/lightdm.conf.d/99-fingerprint-greeter.conf
```

was absent at boot.

The cause was procedural: the rollback command that removes the override had been placed immediately before the reboot instructions and was executed as part of the sequence.

Therefore the first reboot was not a valid test of the patched greeter.

This is an important documentation lesson:

```text
normal activation commands and emergency rollback commands must never be presented as one continuous execution sequence
```

---

## Correct activation — SUCCESS

The override was recreated:

```ini
[Seat:*]
greeter-session=slick-greeter-fingerprint
```

Then `lightdm --show-config` was checked again and confirmed the custom greeter selection.

The machine was rebooted without removing the override.

Result:

```text
touch fingerprint -> desktop
```

No Enter key was required.
No Log In click was required.

This proves the upstream backport works correctly on this Linux Mint 22.3 / slick-greeter 2.2.6 setup when the patched greeter is actually selected.

---

## Final status matrix

```text
Fingerprint authentication itself             PASS
Fresh-boot authentication persistence          PASS
LightDM fingerprint authentication             PASS
Exact upstream root cause                      CONFIRMED
Exact upstream fix                             CONFIRMED
Fix cherry-picks onto 2.2.6                    PASS
Patched source logic                           PASS
Local build                                    PASS
Runtime dependency compatibility               PASS
No RPATH/RUNPATH                               PASS
Mint asset prefix                              PASS
Stock greeter preserved                        PASS
APT rollback package                           AVAILABLE
Patched binary staged separately               PASS
Custom xgreeter session                        PASS
Custom LightDM override                        PASS
LightDM launches patched greeter                PASS by observed behavior
Fingerprint -> desktop with no Enter/click     PASS
```

The primary optimization objective is complete.

---

## Remaining validation worth doing

Although the target behavior is now proven, the isolated greeter should still be exercised through the remaining ordinary login paths before this setup is considered completely frozen:

```text
wrong fingerprint -> password fallback
normal password login
another reboot -> fingerprint direct-to-desktop remains working
TTY rollback -> stock greeter returns normally
```

These are validation/rollback tests, not blockers for the confirmed primary behavior.

---

## Rollback

Emergency rollback should be treated as a separate procedure, not as part of normal setup.

From a TTY if necessary, remove only the custom selection override:

```bash
sudo rm /etc/lightdm/lightdm.conf.d/99-fingerprint-greeter.conf
```

Then reboot:

```bash
sudo reboot
```

LightDM will return to Mint's stock `slick-greeter` session.

Optional cleanup after rollback:

```bash
sudo rm /usr/share/xgreeters/slick-greeter-fingerprint.desktop
sudo rm /usr/local/libexec/slick-greeter-fingerprint
```

If Mint-owned greeter files ever need restoration:

```bash
sudo apt install --reinstall slick-greeter
```

---

## What must be preserved in this repository

Unlike the Validity fingerprint-driver path, this greeter optimization does not depend on private hardware blobs or generated calibration data.

The important reproducibility anchors are public and immutable enough for normal reconstruction:

```text
upstream repository: https://github.com/linuxmint/slick-greeter
baseline tag:         2.2.6
baseline commit:      d1f81b4406d5a756d2274c3dbbbd39bd1bd0f6d4
fix commit:           6902ed325ef358ed4cf3af0b7f04a0d078d18d4e
```

Therefore no compiled greeter binary needs to be committed to this repository.

The guide plus the exact upstream tag/commit hashes are sufficient to rebuild the patched executable reproducibly on a fresh installation.

Do not commit:

```text
/usr/sbin/slick-greeter binary copies
locally built ELF binaries
entire upstream source clone
```

A local patch file could be archived as an optional convenience, but it is not required because the exact upstream fix commit is already recorded.

---

## Future Linux Mint major-upgrade workflow

After a future Mint upgrade, especially beyond Zena:

```text
1. check installed slick-greeter version
2. test fingerprint login before applying any custom greeter
3. check whether Mint now includes upstream commit 6902ed3 or equivalent behavior
4. if fingerprint already opens the desktop directly, remove/avoid the local patched greeter
5. only rebuild/reapply if the distro still lacks the behavior and compatibility is confirmed
6. re-test fingerprint and password fallback after the upgrade
```

The custom greeter should never be carried forward automatically once Mint ships the upstream behavior itself.

---

## Final path in one sentence

> On Linux Mint 22.3 Zena with slick-greeter 2.2.6, upstream commit `6902ed325ef358ed4cf3af0b7f04a0d078d18d4e` cleanly backports onto the exact `2.2.6` source, builds against Mint's existing runtime and asset layout, can be staged beside the untouched stock greeter, and successfully changes fresh-boot login from `touch fingerprint -> Enter/click -> desktop` to `touch fingerprint -> desktop`.