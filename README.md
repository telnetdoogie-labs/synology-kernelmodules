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

## Experimental - Legacy builds

I've been attempting to build for older kernels, as yet unsuccessfully, but I leave a trail here lest someone can continue and make it work
I have made a 'legacy' Dockerfile for these older builds, where older compilers and OSes are required nmaybe.

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
Currently, `entrypoint.sh` reads the `PLATFORM` value that's passed in, and uses that to set up the DSM toolchain which downloads the cross-compiler and sets the environment up for build.

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
