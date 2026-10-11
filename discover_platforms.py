#!/usr/bin/env python3
"""List the x86_64 Synology platforms that can be built, straight from Synology's archive.

Reads https://archive.synology.com/download/ToolChain and prints JSON keyed by
platform, with the toolchain URL, kernel source URL and kernel version for each:

  {
    "apollolake": {
      "toolchain": "https://global.synologydownload.com/.../apollolake-gcc1220_glibc236_x86_64-GPL.txz",
      "kernel": "https://global.synologydownload.com/.../apollolake/linux-4.4.x.txz",
      "release": "7.4-90080",
      "VERSION": "4", "PATCHLEVEL": "4", "SUBLEVEL": "302", "EXTRAVERSION": "+",
      "ARCH": "x86_64",
      "CROSS_COMPILE": "/usr/local/x86_64-pc-linux-gnu/bin/x86_64-pc-linux-gnu-"
    },
    ...
  }

Synology's releases are sparse (a release often only re-publishes a few
platforms), so each platform uses the newest DSM 7 release that contains it.
A platform appears as soon as Synology publishes both a toolchain and kernel
source for it.

Usage:
  discover_platforms.py [--dsm 7.2] [--summary FILE]

  --dsm      only use releases for this DSM version (e.g. "7.2" also matches 7.2.1, 7.2.2)
  --summary  also write a Markdown table of what was found

Works on Python 3.6+ with only the standard library.
"""

import argparse
import json
import re
import sys
import urllib.request

ARCHIVE = "https://archive.synology.com/download/ToolChain"
TOOLCHAIN_INDEX = ARCHIVE + "/toolchain"
GPL_INDEX = ARCHIVE + "/Synology%20NAS%20GPL%20Source"
DL = r"https://global\.synologydownload\.com/download/ToolChain"

RELEASE_RE = re.compile(
    r'href="/download/ToolChain/(?:toolchain|Synology%20NAS%20GPL%20Source)/(\d+(?:\.\d+)+-\d+)"')
TOOLCHAIN_RE = re.compile(
    r'href="(' + DL + r'/toolchain/[^"]+/([A-Za-z0-9]+)-gcc\d+_glibc\d+_x86_64-GPL\.txz)"')
KERNEL_RE = re.compile(
    r'href="(' + DL + r'/Synology%20NAS%20GPL%20Source/[^"/]+/([a-z0-9]+)/linux-(\d+)\.(\d+)\.x\.txz)"')

# The full kernel version DSM 7 runs for each kernel series. The module's
# vermagic must match it exactly. Synology hasn't changed these within DSM 7;
# a new series (e.g. 6.x) needs a line added here.
DSM7_KERNELS = {
    ("3", "10"): ("108", ""),
    ("4", "4"): ("302", "+"),
    ("5", "10"): ("55", "+"),
}
CROSS_COMPILE = "/usr/local/x86_64-pc-linux-gnu/bin/x86_64-pc-linux-gnu-"


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "synology-kernelmodules"})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                return resp.read().decode("utf-8", "replace")
        except OSError as err:
            if attempt == 2:
                sys.exit("error: could not fetch {}: {}".format(url, err))


def version_tuple(release):
    return tuple(int(x) for x in release.split("-")[0].split("."))


def releases(index_url, dsm):
    """DSM 7+ releases on an index page, newest build first."""
    found = set(RELEASE_RE.findall(fetch(index_url)))
    wanted = []
    for rel in found:
        ver = version_tuple(rel)
        if ver[0] < 7:
            continue
        if dsm and ver[:len(dsm)] != dsm:
            continue
        wanted.append(rel)
    return sorted(wanted, key=lambda r: int(r.rsplit("-", 1)[1]), reverse=True)


def newest_per_platform(index_url, link_re, dsm):
    """{platform: (release, match groups)} from the newest release containing each platform."""
    result = {}
    for rel in releases(index_url, dsm):
        for m in link_re.finditer(fetch(index_url + "/" + rel)):
            result.setdefault(m.group(2).lower(), (rel, m.groups()))
    return result


def discover(dsm=None):
    toolchains = newest_per_platform(TOOLCHAIN_INDEX, TOOLCHAIN_RE, dsm)
    kernels = newest_per_platform(GPL_INDEX, KERNEL_RE, dsm)

    platforms = {}
    unknown = []
    for name in sorted(set(toolchains) & set(kernels)):
        tc_rel, (tc_url, _) = toolchains[name]
        kn_rel, (kn_url, _, ver, patch) = kernels[name]
        if (ver, patch) not in DSM7_KERNELS:
            unknown.append("{} (linux-{}.{}.x, {})".format(name, ver, patch, kn_rel))
            continue
        sub, extra = DSM7_KERNELS[(ver, patch)]
        platforms[name] = {
            "toolchain": tc_url,
            "kernel": kn_url,
            "release": kn_rel,
            "toolchain_release": tc_rel,
            "VERSION": ver,
            "PATCHLEVEL": patch,
            "SUBLEVEL": sub,
            "EXTRAVERSION": extra,
            "ARCH": "x86_64",
            "CROSS_COMPILE": CROSS_COMPILE,
        }
    for name in sorted(set(toolchains) - set(kernels)):
        print("note: skipping {}: toolchain published but no kernel source".format(name), file=sys.stderr)
    # Fail rather than quietly drop a platform: a new kernel series needs its full
    # version added to DSM7_KERNELS before its modules can get the right vermagic.
    if unknown:
        sys.exit("error: unknown kernel series, add it to DSM7_KERNELS in discover_platforms.py: "
                 + ", ".join(unknown))
    return platforms


def main():
    ap = argparse.ArgumentParser(description="List buildable Synology platforms from archive.synology.com")
    ap.add_argument("--dsm", help='DSM version to use sources from, e.g. "7.2" (default: newest)')
    ap.add_argument("--summary", help="write a Markdown table of the platforms found to this file")
    args = ap.parse_args()

    dsm = None
    if args.dsm:
        if not re.match(r"^\d+(\.\d+)*$", args.dsm):
            sys.exit('error: --dsm must look like "7.2"')
        dsm = tuple(int(x) for x in args.dsm.split("."))

    platforms = discover(dsm)
    if not platforms:
        sys.exit("error: no platforms found" + (" for DSM " + args.dsm if dsm else ""))

    print(json.dumps(platforms, indent=2))

    if args.summary:
        rows = ["| Platform | Kernel | Kernel source | Toolchain |", "| --- | --- | --- | --- |"]
        for name, p in platforms.items():
            rows.append("| {} | `{}.{}.{}{}` | {} | {} |".format(
                name, p["VERSION"], p["PATCHLEVEL"], p["SUBLEVEL"], p["EXTRAVERSION"],
                p["release"], p["toolchain_release"]))
        with open(args.summary, "w") as f:
            f.write("\n".join(rows) + "\n")


if __name__ == "__main__":
    main()
