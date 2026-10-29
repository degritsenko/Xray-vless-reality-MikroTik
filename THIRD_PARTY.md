# Third-party runtime components

- Xray 26.9.9: official architecture-specific release, verified using the SHA256 values in `build/xray-checksums.txt`. Its MPL-2.0 license is included at `/usr/share/licenses/xray/LICENSE`. Source: https://github.com/XTLS/Xray-core/tree/v26.9.9.
- ARMv5 BusyBox 1.38.0-glibc base: the runtime executable is rebuilt from checksum-verified upstream source for ARMv5TE/soft-float with dpkg/dpkg-deb/rpm/rpm2cpio disabled. Source and build details are in `/usr/share/licenses/busybox/NOTICE`, its actual configuration in `build.config`, and GPL-2 license text in `LICENSE` and `/usr/share/common-licenses/GPL-2`.
- Debian ARMv5 runtime executables and libraries: each owning package's copyright/license notice is copied to `/usr/share/licenses/<package>/copyright`, including referenced standard licenses in `/usr/share/common-licenses`. Exact versions and architecture are recorded at `/usr/share/xray/runtime-packages.txt`.
- The CA certificate bundle and timezone database retain their Debian package copyright notices. No Debian package manager or build/audit tools are included in the final image.

The existing non-ARMv5 Alpine runtimes keep Alpine's package license metadata; Xray's license is added separately.
