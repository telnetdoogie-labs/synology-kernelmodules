# Compiling Optional Kernel Modules for Synology

## (Primarily motivated by docker v28 requiring iptables_raw modules) - but could be extended and used for other things.

---

## Using Docker

I am just using docker now which automates all the above. All you have to pass is the platform name, like `apollolake` or `geminilake`

- mapping a volume like the below will automatically pull the created modules out of the build onto the host for publishing.

| :warning: I strongly advise you DO NOT run this in a container on your NAS as the host. The toolkit specifically advises against that, and I think given what it does with `/proc` it might not be a great idea. |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

```
docker build -t compile_modules .
docker run --privileged --rm -v ./compiled_modules:/compiled_modules:rw -e PLATFORM=apollolake compile_modules
```

### Where the platforms come from

There's no platform list to maintain. Each build reads [Synology's toolchain archive](https://archive.synology.com/download/ToolChain) and uses the toolchain and kernel source from the newest DSM 7 release that includes your platform. New platforms are buildable as soon as Synology publishes their sources, and platforms Synology stops updating keep building from their last release.

- **List the platforms:** run the container without `PLATFORM`, or run `python3 discover_platforms.py | jq -r 'keys[]'`.
- **Match an older DSM:** add `-e DSM_VERSION=7.2` to build from DSM 7.2 sources instead of the newest.
- **Pin exact sources:** mount your own file with `-v ./my_platforms.json:/synology-toolkit/platforms.json:ro`. Use the format `discover_platforms.py` prints.

The kernel version each platform runs (e.g. `4.4.302+`) comes from a small table in `discover_platforms.py` covering DSM 7's three kernel series. That's the only thing to update, and only if Synology moves to a new kernel series. Discovery fails with an error naming the platform if that happens, so it can't be missed.

## Using GitHub Actions

The `Build Kernel Modules` workflow (`.github/workflows/build-modules.yml`) runs the same Docker build on GitHub's runners, one parallel job per platform, so you don't need a Linux box at all.

- **Run it manually:** Actions → _Build Kernel Modules_ → _Run workflow_. Enter `all` or a list of platforms such as `apollolake, geminilake`, and optionally a DSM version such as `7.2`.
  - Tick _Open a pull request…_ to have the results committed to `compiled_modules/` in a PR.
  - Tick _Also build 3.x-kernel platforms_ to try the experimental legacy image as well.
- **Automatically:** it builds every platform whenever the build files change on a PR or on `main`.
- **Weekly:** every Monday it checks Synology's archive. Any platform whose toolchain or kernel source differs from what `compiled_modules/` was built from (recorded in `compiled_modules/sources.json`) is rebuilt, and a PR with the new modules is opened. New platforms are picked up the same way. If nothing changed, nothing is built.
- **Releases:** pushing a tag like `v1.2.0` builds everything and attaches one zip per platform to a GitHub Release, plus `sources.json` listing the exact toolchain and kernel URLs used.

Each run lists the platforms it found in the run summary, checks that the expected `.ko` files were produced, and checks that their `vermagic` matches the platform's kernel version. Download the results from the run's **Artifacts** section: there is one `modules-<platform>` artifact per platform, plus a combined `compiled_modules`.

For forks: the PR option and the weekly PR require _Settings → Actions → General → Allow GitHub Actions to create and approve pull requests_. GitHub also pauses scheduled workflows after 60 days without repository activity; re-enable it from the Actions tab if that happens.

## Experimental - Legacy builds

Older platforms (avoton, braswell, bromolow, grantley, cedarview) run Linux 3.10, which needs the 'legacy' Dockerfile with an older compiler. These builds haven't been tested on hardware yet.

Only `iptable_raw.ko` and `ip6table_raw.ko` are built for 3.10. overlayfs arrived in Linux 3.18, and Synology's 3.10 kernel source doesn't include it (it ships aufs instead), so there is no `overlay.ko` for these platforms.

```
docker build -t compile_modules_legacy ./Dockerfile_legacy
docker run --privileged --rm -v ./compiled_modules:/compiled_modules:rw -e PLATFORM=avoton compile_modules_legacy
```

#### Once run for your platform, your modules should be available in the appropriate folders for copying to your synology. Given the above setup, they're in (for example):

- `compiled_modules/4.4.302+/apollolake/iptable_raw.ko`
- `compiled_modules/4.4.302+/apollolake/ip6table_raw.ko`

#### If you're on a linux box or have WSL, you can check the details of the mod by running, for example:

- `sudo modinfo net/ipv4/netfilter/iptable_raw.ko` - The `vermagic` line has to match the kernel version of your NAS precisely (including the `+` suffix):

```
filename:       net/ipv4/netfilter/iptable_raw.ko
license:        GPL
depends:        ip_tables
retpoline:      Y
vermagic:       4.4.302+ SMP mod_unload
```

#### You can now copy these files to your NAS in `/lib/modules`

#### Change the permissions and ownership of the new `.ko` files on the NAS:

```
sudo chown root:root /lib/modules/{iptable_raw.ko,ip6table_raw.ko}
sudo chmod 644 /lib/modules/{iptable_raw.ko,ip6table_raw.ko}
```

#### Load the modules one time:

```
sudo insmod /lib/modules/ip6table_raw.ko
sudo insmod /lib/modules/iptable_raw.ko
```

#### Assuming you received no errors, validate they're loaded:

```
$ sudo lsmod | grep raw
iptable_raw             1452  0
ip6table_raw            1456  0
ip6_tables             14933  14 ip6table_filter,ip6table_raw
ip_tables              14342  4 iptable_filter,iptable_mangle,iptable_nat,iptable_raw
x_tables               17395  24 ip6table_filter,xt_ipvs,xt_iprange,xt_mark,xt_recent,ip_tables,xt_tcpudp,ipt_MASQUERADE,xt_geoip,xt_limit,xt_state,xt_conntrack,xt_LOG,xt_mac,xt_nat,xt_set,xt_multiport,iptable_filter,ip6table_raw,xt_REDIRECT,iptable_mangle,ip6_tables,xt_addrtype,iptable_raw
```

#### If you want to load the libraries on startup, add the `insmod` lines from above to a Scheduled Task, running as `root` on boot, or add to a service that is loading modules on startup.

---

## If you want to modify this...

`entrypoint.sh` is where everything happens. If you include additional files be sure to modify the Dockerfile to copy them into the container on build.
Currently, `entrypoint.sh` reads the `PLATFORM` value that's passed in, looks it up with `discover_platforms.py`, and uses that to set up the DSM toolchain which downloads the cross-compiler and sets the environment up for build.

`apply_patches.sh` gets called from `entrypoint.sh` before compilation, in case any modifications are needed to config or source.

Once module compilations are complete, compiled modules are copied out to the `/compiled_modules` folder

So... if you want to make significant changes to this, `entrypoint.sh` is the place to start.

The way this is set up currently (the way I run it, with `--rm`) the container is stateless so DSM toolchain downloads etc happen anew each time.

Happy tinkering!

## Contributing

PRs are **VERY** welcome here. Many of the recent updates have been contributed by users just like you.

1. Open an [Issue](https://github.com/telnetdoogie-labs/synology-kernelmodules/issues)
2. [Fork the repo](https://github.com/telnetdoogie-labs/synology-kernelmodules/fork)
3. Make and test your change on real hardware
4. Submit a PR back to this repo, and link with a comment to the Issue you created.
5. Provide details on what you did, what you've tested it on, and the results of those tests.
