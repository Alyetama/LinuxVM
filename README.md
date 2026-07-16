# Linux VM

Spin up throwaway Linux VMs on an Apple Silicon Mac. You pick a distro and how much CPU, RAM, and disk it gets; the app grabs a cloud image, boots it, and lets cloud-init set up the login and tools on the first boot. There's no installer to sit through.

I built it because I wanted a scratch Linux box in under a minute without babysitting a Subiquity screen.

![Linux VM screenshot](docs/mockup.png)

## Download

**[⬇︎ Download for macOS](https://github.com/Alyetama/LinuxVM/releases/latest/download/LinuxVM.dmg)**

Needs an Apple Silicon Mac (M1 or later) on macOS 14+.

That link always resolves to the newest build, since the DMG filename never changes. The [Releases](https://github.com/Alyetama/LinuxVM/releases) page has the changelog.

## Features

- Ubuntu, Debian, or Fedora, using their ARM64 cloud images. Debian works with nothing extra; Ubuntu and Fedora ship qcow2 images, so those want a one-time `brew install qemu` to convert.
- New VMs configure themselves on first boot through cloud-init, so you never touch an installer.
- Set a username and password once. It lives in the Keychain, and every VM you make afterward reuses it.
- The dashboard shows real CPU, memory, disk, and disk I/O for each running VM. It reads them over SSH with a key the app sets up on its own.
- Want a full dev box? Flip one switch and the VM boots with Oh My Zsh (Spaceship prompt, autosuggestions, syntax highlighting), Oh My Tmux, Docker and Compose, Miniforge, plus ripgrep, fd, and bat.
- Put a VM's disk wherever you like, which is handy for keeping big images off your boot drive.
- Don't have the local horsepower? Point it at a Linux box running libvirt over SSH and it'll provision the VM there instead, same dashboard either way.
- Nine color themes if the default isn't your thing: Dracula, Nord, Tokyo Night, Catppuccin, Gruvbox, Solarized, One Dark, and Monokai.
- It runs on Apple's Virtualization.framework. No Docker, no UTM, and no QEMU at all for Debian.

## First launch (opening an unsigned app)

**LinuxVM isn't signed with an Apple Developer ID**, so macOS blocks it the
first time you open it. That's expected. Do one of these once and it opens
normally from then on.

**1. Right-click to open.** In Finder, **Control-click** (or right-click)
`LinuxVM`, choose **Open**, then click **Open** again in the dialog.

**2. If macOS still won't let you (newer versions):** open
**System Settings → Privacy & Security**, scroll down to the message about
`LinuxVM` being blocked, and click **Open Anyway**. Confirm with
**Open Anyway** (and Touch ID or your password if asked).

**3. Terminal fallback.** If neither works, strip the quarantine flag and open
it normally:

```bash
/usr/bin/xattr -dr com.apple.quarantine /Applications/LinuxVM.app
```

(Change the path if you keep the app somewhere other than `/Applications`.)

## Build from source

```bash
git clone https://github.com/Alyetama/LinuxVM.git
cd LinuxVM
./build.sh install   # compiles, bundles, signs, and installs to /Applications
```

You'll need the Xcode command-line tools or a Swift toolchain. [build.sh](build.sh) also takes `run` and plain-build if you don't want the install step.

## License

[MIT](LICENSE) © 2026 Alyetama
