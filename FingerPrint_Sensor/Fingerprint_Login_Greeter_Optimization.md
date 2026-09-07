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

## Verification against the installed Mint build

The installed binary was checked for the newer upstream logic with:

```bash
strings /usr/sbin/slick-greeter | grep -F "Login immediately if PAM interacted"
```

Result:

```text
no output
```

This is consistent with the installed `slick-greeter 2.2.6+zena` build not containing the newer July 2026 auto-login behavior.

This does **not** mean Linux Mint as a whole is outdated. It means the currently installed Mint greeter package does not yet contain this specific upstream change.

---

## Current assessment

```text
Fingerprint authentication itself         WORKING
Fresh-boot authentication persistence      WORKING
LightDM receives successful authentication WORKING
slick-greeter starts session automatically NOT YET
Final Enter/click still required            YES
```

Current usable workflow:

```text
touch finger -> press Enter -> desktop
```

Desired workflow:

```text
touch finger -> desktop
```

Because upstream has already implemented the exact desired behavior with a focused change, this path currently qualifies as worth investigating further.

---

## Planned implementation direction

Do **not** patch `/usr/sbin/slick-greeter` directly.

The preferred route is:

1. obtain the source corresponding as closely as possible to Mint's installed `2.2.6+zena` package;
2. compare it with upstream commit `6902ed325ef358ed4cf3af0b7f04a0d078d18d4e`;
3. verify that the change can be applied cleanly to the installed-version source;
4. build a local package or otherwise stage the change in a reversible way;
5. keep the distro package and rollback path intact;
6. test correct fingerprint login;
7. test wrong fingerprint and password fallback;
8. test reboot persistence;
9. only keep the change if the login flow becomes:

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
Installed build contains fix               NO EVIDENCE / APPEARS ABSENT
Local source comparison                    NEXT
Reversible build/package test              PENDING
Automatic fingerprint -> desktop login     PENDING
Major Mint upgrade workflow                RESERVED FOR FINAL SUCCESS
```

---

## Current path in one sentence

> Fingerprint authentication already succeeds at the Linux Mint boot login screen, but slick-greeter `2.2.6+zena` still requires an extra Enter/click after authentication; upstream commit `6902ed3` fixes this exact PAM/fingerprint interaction, so the next goal is to test that focused change through a reversible local greeter build rather than altering PAM or replacing the login manager.
