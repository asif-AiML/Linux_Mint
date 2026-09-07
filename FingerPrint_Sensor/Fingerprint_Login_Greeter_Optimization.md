# Fingerprint Login Greeter Optimization — Linux Mint / LightDM / slick-greeter

**Project:** Fingerprint reader system integration on Linux Mint  
**Machine:** HP EliteBook 840 G6  
**Sensor:** Synaptics `06cb:00b7`  
**OS:** Linux Mint 22.3 Zena  
**Display manager:** LightDM `1.30.0-0ubuntu14`  
**Greeter:** slick-greeter `2.2.6+zena`  

---

## Why this path exists

The fingerprint reader is already working system-wide through the native Linux authentication stack:

```text
sudo authentication         PASS
Cinnamon lock-screen        PASS
fresh-boot fingerprint auth PASS
password fallback           PASS
reboot persistence          PASS
```

The remaining issue is not fingerprint detection, `libfprint`, `fprintd`, or PAM authentication itself.

The issue is specifically the **fresh-boot LightDM login-screen workflow**.

After reboot, the greeter asks for the fingerprint. The enrolled fingerprint is accepted successfully, but the session does not start immediately. The user must still either:

```text
click the Log In button
```

or:

```text
press Enter
```

So the current boot-login workflow is:

```text
touch fingerprint sensor -> press Enter -> desktop
```

The old PIN-based workflow was approximately:

```text
type 4-digit PIN -> press Enter -> desktop
```

Therefore fingerprint login is usable and slightly lower-effort, but the gain is smaller than expected because slick-greeter still requires one final confirmation action.

---

## Scope and decision rule

This path is deliberately narrow.

The goal is only to remove the unnecessary final Enter/click **if it can be done cleanly and reversibly**.

Proceed only if the solution is one of:

```text
supported configuration change
small reversible slick-greeter change
small upstream-backed package patch
```

Stop if it requires:

```text
replacing LightDM
replacing slick-greeter with another greeter
fragile PAM hacks
large custom login-manager maintenance
unsafe direct modification of login binaries without rollback
```

The expected benefit is modest, so the technical risk and maintenance cost must stay modest too.

---

## Confirmed active login stack

Installed packages:

```text
lightdm          1.30.0-0ubuntu14
lightdm-settings 2.1.1
slick-greeter    2.2.6+zena
```

Effective LightDM configuration:

```text
[Seat:*]
greeter-session=slick-greeter
user-session=cinnamon
```

The greeter selection comes from:

```text
/usr/share/lightdm/lightdm.conf.d/90-slick-greeter.conf
```

Mint's user-session override comes from:

```text
/etc/lightdm/lightdm.conf.d/70-linuxmint.conf
```

No custom greeter override was found under `/etc/lightdm`.

---

## Configuration-only investigation

The installed slick-greeter GSettings schema was inspected:

```text
/usr/share/glib-2.0/schemas/x.dm.slick-greeter.gschema.xml
```

The schema exposes settings for areas such as:

```text
backgrounds
themes
icons
fonts
HiDPI
clock
keyboard
accessibility
monitor placement
```

No setting exists for:

```text
fingerprint auto-submit
auto-login after successful PAM authentication
automatic session start after fingerprint success
login-button bypass
```

Conclusion:

```text
config-only fix -> NOT AVAILABLE
```

---

## Root cause identified upstream

Current upstream slick-greeter contains a fix for this exact fingerprint-login behavior.

Relevant upstream commit:

```text
6902ed325ef358ed4cf3af0b7f04a0d078d18d4e
```

Commit title:

```text
Don't force authenticated user to press the Log In button
```

Date:

```text
2026-07-01
```

The commit explains the exact failure mode:

- slick-greeter previously required a PAM **prompt** before automatically starting the session;
- `pam_fprintd` does not necessarily issue a normal prompt;
- instead, it sends an informational PAM **message**, such as asking the user to place a finger on the sensor;
- fingerprint authentication can therefore complete successfully while slick-greeter still believes no valid user interaction occurred;
- the greeter then shows an authenticated state but waits for the user to press **Log In** or Enter.

This matches the observed Linux Mint 22.3 behavior exactly.

---

## Exact 2.2.6 source confirmation

The upstream repository exposes an exact `2.2.6` tag.

```text
refs/tags/2.2.6      -> annotated tag object 04cf4987ac32ab8656c49787b08b8a5fa1cde78d
refs/tags/2.2.6^{}   -> commit d1f81b4406d5a756d2274c3dbbbd39bd1bd0f6d4
```

The tagged `2.2.6` source was inspected directly and contains the old authentication logic:

```vala
protected bool prompted = false;
```

and:

```vala
if (prompted && !unacknowledged_messages)
```

Its message handler also marks any PAM message as unacknowledged:

```vala
protected void show_message_cb (string text, LightDM.MessageType type)
{
    unacknowledged_messages = true;
    show_message (text, type == LightDM.MessageType.ERROR);
}
```

This confirms the source-level cause:

```text
pam_fprintd sends an informational message
        ↓
slick-greeter 2.2.6 does not count it as a prompt
        ↓
fingerprint authentication succeeds
        ↓
greeter does not auto-start the session
        ↓
Enter / Log In is still required
```

---

## What the upstream fix changes

The older logic tracks whether the user was `prompted`.

The newer logic tracks whether any valid PAM authentication interaction was seen:

```text
prompted
    ->
auth_interaction_seen
```

It also distinguishes PAM informational messages from PAM error messages.

Conceptually, the new decision becomes:

```text
user selected
+ authentication succeeded
+ valid PAM prompt or informational message occurred
+ no blocking error message remains
= start session automatically
```

The fix is therefore not a fingerprint-driver workaround and not a PAM bypass. It is a greeter-side correction to how successful PAM interaction is interpreted.

---

## Installed Mint build verification — correction

An earlier check used:

```bash
strings /usr/sbin/slick-greeter | grep -F "Login immediately if PAM interacted"
```

and produced no output.

That test is **not valid evidence** that the installed Mint binary lacks the upstream fix because the searched phrase is a source-code comment. Compiler output normally does not retain such comments in the executable.

Therefore the correct conclusion is:

```text
exact upstream 2.2.6 source lacks the fix        CONFIRMED
Mint's exact 2.2.6+zena packaged source state   NOT YET PROVEN
installed binary membership of the fix           NOT CONCLUSIVELY DETERMINED
```

The observed login behavior remains fully consistent with the old 2.2.6 logic, but behavior alone is not treated as a source-level proof of Mint's exact package contents.

---

## Local source workspace

The exact upstream `2.2.6` tag was cloned into the fingerprint experiment workspace:

```text
~/fingerprint-path1/slick-greeter-2.2.6
```

Clone target commit:

```text
d1f81b4406d5a756d2274c3dbbbd39bd1bd0f6d4
```

The clone was intentionally created at the tag and therefore starts in detached-HEAD state. This is acceptable because the tree is being used as a frozen reference/build workspace rather than as a normal development branch.

Because the clone used `--depth 1`, the July 2026 fix commit was not initially present locally. It was fetched explicitly:

```bash
git fetch origin 6902ed325ef358ed4cf3af0b7f04a0d078d18d4e
```

No system files were modified by this step.

---

## Backport compatibility test — PASS

The exact upstream fix was cherry-picked onto the exact `2.2.6` source tree:

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
merge conflicts: NONE
```

This is strong evidence that the upstream fingerprint-login fix is structurally compatible with the exact `2.2.6` codebase.

The changed files are:

```text
src/greeter-list.vala
src/user-list.vala
tests/test.vala
```

The actual runtime behavior change is small; a significant part of the added lines consists of tests for message-based authentication and ensuring no-prompt authentication still requires confirmation.

Current local patched commit:

```text
75d95a9
```

This commit is only inside the local experimental clone and has not replaced or modified the installed greeter.

---

## Build-system inspection

The `2.2.6` source uses Meson and is written primarily in Vala/C.

Top-level project declaration:

```text
project('slick-greeter', 'vala', 'c', version : '2.2.6', meson_version : '>= 0.49.0')
```

Observed build dependencies:

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

Executable targets are defined in:

```text
src/meson.build
```

This dependency surface is consistent with a normal GTK3/LightDM greeter and does not show any unusual new dependency introduced by the fingerprint fix.

---

## Local build stage — SUCCESS

Meson `1.12.0` from the existing project-local environment was used:

```text
~/fingerprint-path1/tools-venv
```

Missing build dependencies were resolved incrementally:

```text
valac
libcanberra-dev
liblightdm-gobject-1-dev
```

Meson configuration then completed successfully.

The patched source was compiled locally with:

```bash
cd ~/fingerprint-path1/slick-greeter-2.2.6
ninja -C build
```

Result:

```text
Compilation succeeded - 60 warning(s)
[156/156] Linking target src/slick-greeter
```

The warnings are primarily deprecation and nullability warnings from the existing codebase and did not prevent compilation.

Produced executable:

```text
~/fingerprint-path1/slick-greeter-2.2.6/build/src/slick-greeter
```

Observed file information:

```text
-rwxrwxr-x 1 asif asif 1.9M ... build/src/slick-greeter
```

The local build remains isolated inside the experimental workspace. No system greeter file has been replaced.

A `strings` check against the locally built binary using the source-code comment text also produced no output. This is expected and reinforces that such a comment-string search is not a suitable binary verification method.

The patched source itself should instead be verified directly for the new runtime symbol/logic, for example with:

```bash
grep -n "auth_interaction_seen" src/greeter-list.vala
```

---

## Current assessment

```text
Fingerprint authentication itself         WORKING
Fresh-boot authentication persistence      WORKING
LightDM receives successful authentication WORKING
slick-greeter starts session automatically NOT YET
Final Enter/click still required            YES
Exact 2.2.6 source tag                      CONFIRMED
Source-level cause                          CONFIRMED
Upstream fix                                IDENTIFIED
Fix applies cleanly to 2.2.6                PASS
Local patched source tree                   READY
Local Meson configure                       PASS
Local patched compile                       PASS
Patched binary produced                     PASS
System greeter modified                     NO
```

Current usable workflow:

```text
touch finger -> press Enter -> desktop
```

Desired workflow:

```text
touch finger -> desktop
```

Because upstream has already implemented the exact desired behavior with a focused change, because that change cherry-picks cleanly onto the exact `2.2.6` tag, and because the patched tree compiles successfully, this path remains within the project's low-risk/reversible decision rule.

---

## Planned implementation direction

Do **not** patch `/usr/sbin/slick-greeter` directly.

Current planned route:

1. use the exact `2.2.6` tagged source as the baseline;
2. apply only upstream commit `6902ed325ef358ed4cf3af0b7f04a0d078d18d4e`;
3. configure and compile the patched tree locally;
4. verify the patched source contains the intended authentication logic;
5. inspect the produced executable/package layout before any activation;
6. design and document rollback before touching the active greeter;
7. stage the patched greeter in a reversible way rather than blindly overwriting distro files;
8. test correct fingerprint login;
9. test wrong fingerprint and password fallback;
10. test reboot persistence;
11. only keep the change if the login flow becomes:

```text
touch fingerprint -> desktop
```

without degrading password fallback or login reliability.

---

## Rollback requirement

Any implementation in this path must have a clear rollback before it is activated.

At minimum, rollback must restore the stock Mint slick-greeter package or stock executable without depending on the graphical login screen being usable.

No permanent change should be accepted until the rollback procedure has been tested or is trivially guaranteed by package restoration.

---

## Future Linux Mint upgrade workflow — RESERVED

This section is intentionally left incomplete until this path is successfully finished and tested.

When Linux Mint moves beyond Zena or ships a major `slick-greeter` update, the final guide must explain how to determine whether the local workaround is still needed.

The final upgrade workflow should cover:

```text
check new Mint version
check installed slick-greeter version
check whether upstream fingerprint auto-login fix is now included
remove/avoid local patch if Mint ships the fix natively
rebuild/reapply only if the fix is still absent and still compatible
verify fingerprint login and password fallback again
```

The goal is to avoid carrying a custom greeter modification forever once Linux Mint provides the upstream behavior itself.

This section will be finalized only after the current Zena path succeeds.

---

## Current path status

```text
Observed extra Enter/click requirement     CONFIRMED
Active greeter identified                  CONFIRMED
Config-only option                         NOT AVAILABLE
Exact upstream fix                         IDENTIFIED
Upstream commit                            6902ed325ef358ed4cf3af0b7f04a0d078d18d4e
Exact upstream 2.2.6 tag                   CONFIRMED
2.2.6 commit                               d1f81b4406d5a756d2274c3dbbbd39bd1bd0f6d4
Source-level old behavior                  CONFIRMED
Installed 2.2.6+zena source match          NOT YET PROVEN
Installed binary fix presence              NOT CONCLUSIVELY DETERMINED
Clean backport onto 2.2.6                  PASS
Patched local commit                       75d95a9
Build system/dependencies                  MAPPED
Local Meson configure                      PASS
Local patched compile                      PASS
Patched local binary                       BUILT
Reversible activation test                 PENDING
Automatic fingerprint -> desktop login     PENDING
Major Mint upgrade workflow                RESERVED FOR FINAL SUCCESS
```

---

## Current path in one sentence

> Fingerprint authentication already succeeds at the Linux Mint boot login screen, but slick-greeter `2.2.6+zena` still requires an extra Enter/click after authentication; the exact upstream `2.2.6` source contains the old prompt-only logic, upstream commit `6902ed3` fixes this exact PAM/fingerprint behavior, that fix cherry-picks cleanly onto `2.2.6`, and the patched tree now configures and compiles successfully in a local isolated workspace, while the exact source state of Mint's `2.2.6+zena` package remains unproven and no system greeter file has yet been modified.
