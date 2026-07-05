## Linux VM v1.0.0

First public release. Create isolated Linux VMs on Apple Silicon that install and configure themselves automatically via cloud-init — Ubuntu, Debian, or Fedora, a live CPU/memory/disk dashboard, Keychain-backed default credentials, an optional one-click dev toolchain (Oh My Zsh + Spaceship, Docker, Miniforge, ripgrep/fd/bat), and 9 built-in color themes.

## First launch (opening an unsigned app)

**LinuxVM isn't signed with an Apple Developer ID**, so macOS blocks it the
first time you open it. This is expected — you only need to do one of the
following once, and it opens normally afterward.

**1. Right-click to open.** In Finder, **Control-click** (or right-click)
`LinuxVM`, choose **Open**, then click **Open** again in the dialog.

**2. If macOS still won't let you (newer versions):** open
**System Settings → Privacy & Security**, scroll down to the message about
`LinuxVM` being blocked, and click **Open Anyway**. Confirm with
**Open Anyway** (and Touch ID or your password if asked).

**3. Terminal fallback.** If neither works, remove the quarantine flag and open
it normally:

```bash
/usr/bin/xattr -dr com.apple.quarantine /Applications/LinuxVM.app
```

(Adjust the path if you keep the app somewhere other than `/Applications`.)
