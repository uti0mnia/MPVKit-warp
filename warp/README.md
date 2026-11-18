# MPVKit for Warp

This is the mpv and FFmpeg build that Warp ships. It's MPVKit 0.41.0 (`613c0cc`), which builds mpv 0.41.0 with
MPVKit's patches and FFmpeg 8.0.1. Warp's changes are on the `warp-lgpl` branch. With them, mpv and FFmpeg are built
under the LGPL, version 2.1 or later.

## What Warp changes

- **`Sources/BuildScripts/XCFrameworkBuild/main.swift`.** FFmpeg is built without `--enable-nonfree` or
  `--enable-version3`, and uses OpenSSL instead of GnuTLS. GnuTLS needs gmp, nettle and hogweed, which are LGPLv3.
  FFmpeg now reports "LGPL version 2.1 or later". libsmbclient is GPL-only, so it's no longer built.
- **`warp/make-dynamic-libmpv.sh`.** Links mpv, FFmpeg and the libraries they use into one dynamic
  `Libmpv.framework` for each platform. It exports only the `_mpv_*` symbols. The result is
  `dist/dynamic/Libmpv.xcframework`.

## Build

The build takes about 40 minutes on an Apple silicon Mac. It needs Homebrew's `meson`, `ninja` and `pkgconf`.

```sh
PATH=/opt/homebrew/bin:$PATH make build platform=ios,isimulator,tvos,tvsimulator,macos
warp/make-dynamic-libmpv.sh
```

Then copy `dist/dynamic/Libmpv.xcframework` into Warp's `Packages/WarpPlayer/Frameworks/`.

## Use your own build

The LGPL lets you replace mpv or FFmpeg in Warp. Change the sources or flags here and rebuild. Then replace
`Libmpv.framework` inside the app bundle and re-sign the app.
