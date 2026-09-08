# Fingerprint Login Greeter — Fresh Install Success Guide

This is the direct successful path for reproducing the Linux Mint login-screen fingerprint behavior:

```text
touch fingerprint -> desktop
```

with no Enter key and no Log In click.

This guide covers only the **LightDM / slick-greeter optimization**. It assumes the fingerprint reader is already working through `libfprint`, `fprintd`, PAM, and LightDM authentication. For a truly fresh machine, complete the repository's main fingerprint-reader setup guide first, then return here.

Tested environment:

```text
Linux Mint 22.3 Zena
LightDM 1.30.0-0ubuntu14
slick-greeter 2.2.6+zena
HP EliteBook 840 G6
Synaptics 06cb:00b7
```

---

## 1. Verify the prerequisite behavior

Before patching slick-greeter, fingerprint authentication at the boot login screen must already succeed.

Expected prerequisite state:

```text
touch fingerprint -> authentication succeeds -> Enter / Log In -> desktop
```

If fingerprint authentication itself does not work, stop here. This guide does not fix sensor support, `fprintd`, or PAM.

---

## 2. Create a workspace

```bash
mkdir -p ~/fingerprint-path1
cd ~/fingerprint-path1
```

---

## 3. Install build dependencies

The working experiment required Meson, Ninja, Vala, and slick-greeter development libraries.

If the existing fingerprint project virtual environment is already present, it may be reused for Meson/Ninja. Otherwise install them in a local venv:

```bash
python3 -m venv tools-venv
source tools-venv/bin/activate
pip install meson ninja
```

Install the required system development packages:

```bash
sudo apt install valac libcanberra-dev liblightdm-gobject-1-dev \
  libgtk-3-dev libcairo2-dev libglib2.0-dev libx11-dev libpixman-1-dev
```

Using a Python venv during the build is safe. The resulting greeter executable does not depend on that venv at runtime.

---

## 4. Clone the exact upstream slick-greeter baseline

Upstream repository:

```text
https://github.com/linuxmint/slick-greeter
```

Clone exact version `2.2.6`:

```bash
cd ~/fingerprint-path1
git clone --branch 2.2.6 --depth 1 https://github.com/linuxmint/slick-greeter.git slick-greeter-2.2.6
cd slick-greeter-2.2.6
```

Known baseline:

```text
tag:             2.2.6
baseline commit: d1f81b4406d5a756d2274c3dbbbd39bd1bd0f6d4
```

Optional verification:

```bash
git rev-parse HEAD
```

Expected:

```text
d1f81b4406d5a756d2274c3dbbbd39bd1bd0f6d4
```

---

## 5. Fetch and apply the exact upstream fingerprint-login fix

Upstream fix commit:

```text
6902ed325ef358ed4cf3af0b7f04a0d078d18d4e
```

Title:

```text
Don't force authenticated user to press the Log In button
```

Fetch it into the shallow clone:

```bash
git fetch origin 6902ed325ef358ed4cf3af0b7f04a0d078d18d4e
```

Apply it:

```bash
git cherry-pick 6902ed325ef358ed4cf3af0b7f04a0d078d18d4e
```

On the tested system this applied with no merge conflicts.

The local cherry-picked commit became:

```text
75d95a9
```

The exact local SHA may differ if Git metadata changes, so the important immutable anchor is the upstream fix commit above.

---

## 6. Verify the patched source

```bash
grep -n "auth_interaction_seen" src/greeter-list.vala
```

The source should contain multiple `auth_interaction_seen` references, including the authentication-complete logic.

Do not use a source comment with `strings` against the executable as proof; comments are normally compiled out.

---

## 7. Build with Mint's asset prefix

Do **not** use Meson's default `/usr/local` prefix for this build. Mint's slick-greeter assets live under:

```text
/usr/share/slick-greeter
```

Build with `/usr` as the configured prefix:

```bash
rm -rf build
meson setup build --prefix=/usr
ninja -C build
```

Do **not** run:

```text
ninja install
```

The successful build produces:

```text
~/fingerprint-path1/slick-greeter-2.2.6/build/src/slick-greeter
```

Optional asset-path verification:

```bash
strings build/src/slick-greeter | grep -E '/usr/(local/)?share/slick-greeter'
```

Relevant paths should use:

```text
/usr/share/slick-greeter
```

and not `/usr/local/share/slick-greeter`.

---

## 8. Optional runtime compatibility checks

Recommended before staging:

```bash
ldd build/src/slick-greeter
readelf -d build/src/slick-greeter | grep -E 'RPATH|RUNPATH|NEEDED'
```

On the tested system:

```text
all shared libraries resolved from normal system locations
RPATH absent
RUNPATH absent
```

This proves the binary is not tied to the build folder or Python venv.

---

## 9. Confirm stock rollback availability

Before activating anything:

```bash
apt-cache policy slick-greeter
```

On the tested system:

```text
Installed: 2.2.6+zena
Candidate: 2.2.6+zena
```

The recorded stock binary SHA-256 on that system was:

```text
583acf57cd2fdf15db0118649b03983f0ad24c4cbc9a6a8309610fe87667a1aa  /usr/sbin/slick-greeter
```

Do not assume that hash applies to other Mint package builds; use it only as the known-good reference for this tested Zena package.

---

## 10. Stage the patched binary separately

Never overwrite:

```text
/usr/sbin/slick-greeter
```

Create a separate destination:

```bash
sudo mkdir -p /usr/local/libexec
```

Copy the patched binary:

```bash
sudo cp ~/fingerprint-path1/slick-greeter-2.2.6/build/src/slick-greeter \
  /usr/local/libexec/slick-greeter-fingerprint
```

Set ownership and mode:

```bash
sudo chown root:root /usr/local/libexec/slick-greeter-fingerprint
sudo chmod 755 /usr/local/libexec/slick-greeter-fingerprint
```

Verify:

```bash
ls -l /usr/local/libexec/slick-greeter-fingerprint
```

Expected shape:

```text
-rwxr-xr-x 1 root root ... /usr/local/libexec/slick-greeter-fingerprint
```

---

## 11. Create a separate LightDM greeter session

Create:

```bash
sudo nano /usr/share/xgreeters/slick-greeter-fingerprint.desktop
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

Save and verify:

```bash
cat /usr/share/xgreeters/slick-greeter-fingerprint.desktop
```

---

## 12. Select the patched greeter with a tiny LightDM override

Create the override directly:

```bash
printf '[Seat:*]\ngreeter-session=slick-greeter-fingerprint\n' | \
  sudo tee /etc/lightdm/lightdm.conf.d/99-fingerprint-greeter.conf
```

Verify the file exists:

```bash
cat /etc/lightdm/lightdm.conf.d/99-fingerprint-greeter.conf
```

Expected:

```ini
[Seat:*]
greeter-session=slick-greeter-fingerprint
```

Then verify LightDM's resolved configuration:

```bash
lightdm --show-config | grep -A6 '^\[Seat:\*\]'
```

You must see:

```text
greeter-session=slick-greeter-fingerprint
```

with the source pointing to:

```text
/etc/lightdm/lightdm.conf.d/99-fingerprint-greeter.conf
```

---

## 13. Reboot and test

At this point, do **not** remove the override.

Reboot:

```bash
sudo reboot
```

At the login screen, use the enrolled finger.

Successful final behavior:

```text
touch fingerprint -> desktop
```

No Enter key.
No Log In click.

This behavior was confirmed on the tested Linux Mint 22.3 system.

---

## 14. Validate ordinary fallback paths

After confirming direct fingerprint login, also test:

```text
wrong fingerprint -> normal failure / password fallback
normal password login
another reboot -> direct fingerprint login still works
```

The greeter optimization should only be kept if ordinary login remains reliable.

---

# Emergency rollback

This section is intentionally separate from normal installation steps.

Do **not** run these commands during normal activation.

If the custom greeter fails, switch to a TTY such as `Ctrl+Alt+F3`, log in, and remove only the selector override:

```bash
sudo rm /etc/lightdm/lightdm.conf.d/99-fingerprint-greeter.conf
sudo reboot
```

LightDM will fall back to Mint's stock greeter.

Optional cleanup after rollback:

```bash
sudo rm /usr/share/xgreeters/slick-greeter-fingerprint.desktop
sudo rm /usr/local/libexec/slick-greeter-fingerprint
```

If Mint-owned slick-greeter files ever need restoration:

```bash
sudo apt install --reinstall slick-greeter
```

---

# What should be preserved in this repository?

For this greeter optimization, the **guide is enough**.

Unlike the Synaptics/Validity driver work, this path does not depend on hardware-specific binary blobs, calibration data, certificates, or generated device state.

The reproducibility anchors are public upstream Git objects:

```text
repository:      https://github.com/linuxmint/slick-greeter
baseline tag:    2.2.6
baseline commit: d1f81b4406d5a756d2274c3dbbbd39bd1bd0f6d4
fix commit:      6902ed325ef358ed4cf3af0b7f04a0d078d18d4e
```

Therefore there is no need to commit:

```text
compiled slick-greeter binary
entire slick-greeter source clone
copies of /usr/sbin/slick-greeter
```

An exported patch file could be stored as an optional convenience, but it is not necessary because the exact upstream fix commit is recorded and can be fetched directly.

---

# Future Linux Mint upgrade rule

After a future Mint release or a slick-greeter package upgrade:

```text
1. test stock fingerprint login first
2. check the installed slick-greeter version
3. check whether the distro already includes commit 6902ed3 or equivalent behavior
4. if stock fingerprint login already goes directly to the desktop, remove the custom greeter override/binary
5. only rebuild this patch if the distro still lacks the behavior and the old baseline remains compatible
6. re-test fingerprint and password fallback
```

Do not carry the custom greeter forward automatically once Linux Mint ships the fix itself.

---

# Success target

```text
touch fingerprint
        ↓
PAM/fprintd authenticates successfully
        ↓
patched slick-greeter recognizes valid PAM interaction
        ↓
LightDM starts the user session immediately
        ↓
desktop
```

That exact behavior was successfully achieved on the tested system.