#!/usr/bin/env python3
"""Write Markdown notes for a release or a compiled-modules PR.

  release_notes.py --modules compiled_modules --sources compiled_modules/sources.json \
      [--repo owner/name --tag v1.2.0] [--changelog generated.md] [--previous old_sources.json]

--modules     directory laid out as <kernel version>/<platform>/*.ko
--sources     discover_platforms.py output for the platforms that were built
--repo/--tag  link each platform to its zip on that release (zips named <platform>.zip)
--changelog   GitHub's generated release notes, regrouped by conventional-commit prefix
--previous    sources.json from before this build, to show what changed (for PRs)

Prints the notes to stdout. Standard library only.
"""

import argparse
import json
import os
import re
import sys

MODULE_ORDER = ["iptable_raw", "ip6table_raw", "overlay"]

SECTIONS = [
    ("feat", "New features"),
    ("fix", "Fixes"),
    ("ci", "CI and build"),
    ("build", "CI and build"),
    ("docs", "Documentation"),
]
OTHER = "Other changes"


def built_platforms(modules_dir):
    """{platform: (kernel version, [module names])} from the compiled modules tree."""
    found = {}
    for kver in sorted(os.listdir(modules_dir)):
        kdir = os.path.join(modules_dir, kver)
        if not os.path.isdir(kdir):
            continue
        for platform in sorted(os.listdir(kdir)):
            pdir = os.path.join(kdir, platform)
            mods = [f[:-3] for f in os.listdir(pdir) if f.endswith(".ko")]
            mods.sort(key=lambda m: (MODULE_ORDER.index(m) if m in MODULE_ORDER else 99, m))
            if mods:
                found[platform] = (kver, mods)
    return found


def dsm(release):
    return "DSM " + release if release else "unknown"


def platform_table(built, sources, previous=None, repo=None, tag=None):
    head = ["Platform", "Kernel", "Modules", "Built from"]
    if previous is not None:
        head.append("Previously")
    if repo and tag:
        head.append("Download")
    rows = ["| " + " | ".join(head) + " |", "|" + " --- |" * len(head)]
    for platform, (kver, mods) in sorted(built.items()):
        src = sources.get(platform, {})
        row = [platform, "`{}`".format(kver), ", ".join(mods), dsm(src.get("release"))]
        if previous is not None:
            old = previous.get(platform)
            if not old:
                row.append("**new platform**")
            elif old == src:
                row.append("same sources")
            else:
                row.append(dsm(old.get("release")))
        if repo and tag:
            name = platform + ".zip"
            row.append("[{}](https://github.com/{}/releases/download/{}/{})".format(name, repo, tag, name))
        rows.append("| " + " | ".join(row) + " |")
    return "\n".join(rows)


def regroup_changelog(text):
    """Group GitHub's generated "What's Changed" list by conventional-commit prefix and drop bots."""
    groups = {}
    contributors = []
    footer = []
    section = None
    for line in text.splitlines():
        if line.startswith("<!--"):
            continue
        if line.startswith("## "):
            section = line[3:].strip().lower()
            continue
        if line.startswith("**Full Changelog**"):
            footer.append(line)
            continue
        if not line.startswith("* "):
            continue
        if "[bot]" in line:
            continue
        if section == "what's changed":
            m = re.match(r"\* (\w+)(\([^)]*\))?!?:\s*", line)
            title = OTHER
            if m:
                title = dict(SECTIONS).get(m.group(1).lower(), OTHER)
            groups.setdefault(title, []).append(line)
        elif section == "new contributors":
            contributors.append(line)

    out = []
    order = []
    for _, title in SECTIONS + [(None, OTHER)]:
        if title not in order:
            order.append(title)
    for title in order:
        if groups.get(title):
            out += ["### " + title, ""] + groups[title] + [""]
    if contributors:
        out += ["### New contributors", ""] + contributors + [""]
    out += footer
    return "\n".join(out).strip()


def load(path):
    with open(path) as f:
        return json.load(f)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--modules", required=True)
    ap.add_argument("--sources", required=True)
    ap.add_argument("--repo")
    ap.add_argument("--tag")
    ap.add_argument("--changelog")
    ap.add_argument("--previous")
    args = ap.parse_args()

    built = built_platforms(args.modules)
    if not built:
        sys.exit("error: no modules found in " + args.modules)
    sources = load(args.sources)
    previous = None
    if args.previous:
        previous = load(args.previous) if os.path.exists(args.previous) else {}

    legacy = sorted(p for p, (kver, mods) in built.items() if "overlay" not in mods)
    out = []

    if args.tag:
        out += [
            "Optional kernel modules for Synology NAS, compiled from Synology's own DSM toolchains "
            "and kernel sources. Each module's `vermagic` has been checked against the platform's "
            "kernel. They have not been tested on hardware.",
            "",
            "## Which file do I need?",
            "",
            "Run `uname -a` on your NAS. The end of the output names your platform "
            "(for example `synology_geminilake_920+` means **geminilake**), and the kernel version "
            "must match the Kernel column exactly.",
            "",
        ]
    else:
        out += ["## Platforms in this build", ""]

    out += [platform_table(built, sources, previous, args.repo, args.tag), ""]

    if legacy:
        out += [
            "No `overlay.ko` for {}: these run Linux 3.10, and overlayfs only arrived in 3.18 "
            "(Synology's 3.10 kernel ships aufs instead).".format(", ".join(legacy)),
            "",
        ]

    if args.tag:
        out += [
            "`all-platforms.zip` has every platform. `sources.json` lists the exact toolchain and "
            "kernel source URLs each platform was built from.",
            "",
            "## Installing",
            "",
            "Unzip your platform's file on the NAS, then from that folder:",
            "",
            "```sh",
            "for m in *.ko; do",
            "  sudo install -o root -g root -m 644 \"$m\" /lib/modules/",
            "  sudo insmod \"/lib/modules/$m\"",
            "done",
            "lsmod | grep -E 'raw|overlay'",
            "```",
            "",
            "To load them on every boot, add the `insmod` lines to a triggered task in Task "
            "Scheduler that runs as `root` at boot-up. See the "
            "[README](https://github.com/{}#readme) for details.".format(args.repo or ""),
            "",
        ]

    if args.changelog:
        with open(args.changelog) as f:
            changes = regroup_changelog(f.read())
        if changes:
            out += ["## What's changed", "", changes, ""]

    print("\n".join(out).rstrip() + "\n")


if __name__ == "__main__":
    main()
