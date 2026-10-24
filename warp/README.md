# MPVKit for Warp (LGPL, dynamic)

MPVKit 0.41.0 (`613c0cc`, mpv v0.41.0 with MPVKit's patches, FFmpeg n8.0.1) with Warp's changes on branch
`warp-lgpl`:

- `Sources/BuildScripts/XCFrameworkBuild/main.swift`: FFmpeg is configured without `--enable-nonfree` and without
  `--enable-version3`, and with OpenSSL (Apache-2.0) in place of GnuTLS. GnuTLS pulled in gmp, nettle and hogweed,
  which are LGPLv3. FFmpeg then reports "LGPL version 2.1 or later". libsmbclient (GPL-only) is no longer built.
- `warp/make-dynamic-libmpv.sh`: links each platform's static libmpv, FFmpeg and every library under them into one
  dynamic `Libmpv.framework` that exports only `_mpv_*`, then `dist/dynamic/Libmpv.xcframework`.

Build (about 40 minutes on an M-series Mac; needs Homebrew's `meson ninja pkgconf`):

```sh
PATH=/opt/homebrew/bin:$PATH make build platform=ios,isimulator,tvos,tvsimulator,macos
warp/make-dynamic-libmpv.sh
rm -rf ~/Documents/coding/warp.nosync/warp/Packages/WarpPlayer/Frameworks/Libmpv.xcframework
cp -R dist/dynamic/Libmpv.xcframework ~/Documents/coding/warp.nosync/warp/Packages/WarpPlayer/Frameworks/
```

To swap in your own mpv or FFmpeg, as the LGPL allows: change the sources or flags here, rebuild, and replace
`Libmpv.framework` inside the app bundle (re-signing it).
