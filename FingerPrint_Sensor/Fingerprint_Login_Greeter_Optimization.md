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

Mint's normal greeter configuration comes from:

```text
/usr/share/lightdm/lightdm.conf.d/90-slick-greeter.conf
```

and normally selects:

```text
[Seat:*]
greeter-session=slick-greeter
user-session=cinnamon
```

The stock greeter session definition is:

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

The project environment provided Meson `1.12.0` and Ninja `1.13.2`.

---

## Local build — SUCCESS

Compilation completed successfully:

```text
Compilation succeeded - 60 warning(s)
[156/156] Linking target src/slick-greeter
```

Produced executable:

```text
~/fingerprint-path1/slick-greeter-2.2.6/build/src/slick-greeter
```

No system greeter was modified by the build.

---

## Runtime dependency comparison — PASS

`ldd` was run against both the local patched build and `/usr/sbin/slick-greeter`.

Both resolve the same normal system runtime stack, including GTK3, GDK, Cairo, Canberra, LightDM GObject, X11, Pixman, GLib/GIO, Pango, ATK, and related libraries.

No required library is missing, and no runtime dependency is loaded from `~/fingerprint-path1` or `tools-venv`.

Therefore the fact that some build/staging commands were run while the Python virtual environment was active is not relevant to LightDM's boot-time execution. LightDM starts independently as a system service after reboot.

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

The first successful build used Meson's default prefix and embedded `/usr/local/share/slick-greeter` paths. Mint's packaged greeter assets live under `/usr/share/slick-greeter`, so that build was intentionally rejected for staging.

The tree was rebuilt with:

```bash
meson setup build --prefix=/usr
ninja -C build
```

After recompilation, embedded paths resolve to:

```text
/usr/share/slick-greeter
```

with no `/usr/local/share/slick-greeter` paths remaining.

Therefore:

```text
Mint asset-layout compatibility -> PASS
```

---

## Stock package and rollback anchors

Mint's package owns:

```text
/usr/sbin/slick-greeter
/usr/share/slick-greeter/...
/usr/share/xgreeters/slick-greeter.desktop
```

Stock binary anchor:

```text
-rwxr-xr-x 1 root root 424168 Jan 8 2026 /usr/sbin/slick-greeter
```

SHA-256:

```text
583acf57cd2fdf15db0118649b03983f0ad24c4cbc9a6a8309610fe87667a1aa  /usr/sbin/slick-greeter
```

APT confirms the exact package is still available:

```text
Installed: 2.2.6+zena
Candidate: 2.2.6+zena
```

Recovery layers:

```text
remove custom LightDM override -> return to stock session selection
sudo apt install --reinstall slick-greeter -> restore Mint-owned greeter files
```

The stock binary has not been overwritten.

---

## Isolated staging — COMPLETE

The patched executable is staged separately as:

```text
/usr/local/libexec/slick-greeter-fingerprint
```

Observed ownership and mode:

```text
-rwxr-xr-x root root /usr/local/libexec/slick-greeter-fingerprint
```

A separate greeter session entry was created:

```text
/usr/share/xgreeters/slick-greeter-fingerprint.desktop
```

with:

```ini
[Desktop Entry]
Name=Slick Greeter Fingerprint
Comment=Slick Greeter with fingerprint auto-login fix
Exec=/usr/local/libexec/slick-greeter-fingerprint
Type=Application
X-Ubuntu-Gettext-Domain=slick-greeter
```

The intended LightDM override is:

```text
/etc/lightdm/lightdm.conf.d/99-fingerprint-greeter.conf
```

with:

```ini
[Seat:*]
greeter-session=slick-greeter-fingerprint
```

When this file existed before the first reboot attempt, `lightdm --show-config` correctly reported:

```text
H  greeter-session=slick-greeter-fingerprint
```

from:

```text
H  /etc/lightdm/lightdm.conf.d/99-fingerprint-greeter.conf
```

---

## First activation attempt — INVALID TEST, ROOT CAUSE FOUND

The first reboot appeared negative because the login flow remained:

```text
touch fingerprint -> Enter / Log In -> desktop
```

LightDM's boot log showed:

```text
Session pid=...: Running command /usr/lib/lightdm/lightdm-greeter-session /usr/sbin/slick-greeter
```

and never showed the staged patched binary.

A later inspection of the current boot's configuration loading sequence showed that LightDM loaded:

```text
/usr/share/lightdm/lightdm.conf.d/90-slick-greeter.conf
/etc/lightdm/lightdm.conf.d/70-linuxmint.conf
/etc/lightdm/lightdm.conf
```

but did **not** load:

```text
/etc/lightdm/lightdm.conf.d/99-fingerprint-greeter.conf
```

The decisive check then returned:

```text
ls: cannot access '/etc/lightdm/lightdm.conf.d/99-fingerprint-greeter.conf': No such file or directory
```

Therefore the apparent LightDM "show-config vs runtime" discrepancy was not a greeter-session resolution bug. The override file was simply absent by the time LightDM booted.

This means:

```text
patched binary at boot                      NOT YET TESTED
LightDM runtime greeter-session resolution  NOT YET SUSPECT
first reboot result                         INVALID AS PATCH TEST
stock greeter launch                        EXPECTED because override absent
```

The override had definitely existed immediately before the activation sequence because `lightdm --show-config` had reported it. Its later absence explains the entire first reboot result. The exact reason it disappeared is not yet treated as a system bug; one likely sequencing hazard is accidentally executing the documented rollback command before reboot. Future instructions must clearly separate commands to run now from rollback commands that are for emergency use only.

---

## Correct next direction

Do not modify the patch, PAM, LightDM package, or xgreeter session logic.

The next activation attempt should:

```text
1. recreate /etc/lightdm/lightdm.conf.d/99-fingerprint-greeter.conf
2. verify the file exists and has the expected contents
3. verify lightdm --show-config selects slick-greeter-fingerprint
4. reboot without executing the rollback command
5. verify the runtime log launches /usr/local/libexec/slick-greeter-fingerprint
6. only then judge fingerprint auto-login behavior
```

This is now the shortest and lowest-risk way forward.

---

## Current assessment

```text
Observed extra Enter/click requirement      CONFIRMED
Active stock greeter                        slick-greeter 2.2.6+zena
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
APT exact-package rollback                  AVAILABLE
Patched binary staged                       PASS
Custom xgreeter entry                       CREATED
Custom LightDM override                     CURRENTLY ABSENT
First reboot tested patched binary          NO
First reboot patch result                   INVALID / NOT A PATCH TEST
Automatic fingerprint -> desktop login      PENDING
```

---

## Safety rules for the remaining work

- Do not run `ninja install`.
- Do not overwrite `/usr/sbin/slick-greeter`.
- Do not remove the stock xgreeter desktop entry.
- Do not change PAM for this greeter optimization.
- Keep the isolated staged binary and tiny override model.
- Rollback must remain possible from a TTY even if the graphical greeter fails.
- Do not execute the rollback command during normal activation testing.
- Test both fingerprint and password paths only after logs prove the custom binary actually launched.
- If the maintenance cost becomes disproportionate to removing one Enter press, stop and keep the current working flow.

---

## Required tests after verified custom-binary activation

Once the runtime log proves the staged greeter actually launched, test in this order:

```text
1. greeter starts normally
2. runtime log shows /usr/local/libexec/slick-greeter-fingerprint
3. correct fingerprint -> desktop automatically
4. wrong fingerprint -> normal failure / password fallback
5. normal password login still works
6. reboot persistence
7. rollback to stock greeter
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

> The exact upstream fingerprint-login fix cleanly backports onto slick-greeter 2.2.6 and the patched binary is safely staged beside Mint's stock greeter; the first reboot never tested it because the LightDM override file was absent at boot, so the next step is simply to recreate and verify that override, reboot without invoking rollback, prove the custom binary actually launched, and only then evaluate whether fingerprint authentication goes directly to the desktop.