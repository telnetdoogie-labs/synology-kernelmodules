## The hard way (no docker)...

This doc / These notes are from when I first started working on getting the compiles to work before I switched to docker. Leaving them here as a paper trail for when someone wants to do this the traditional way.

---

I ran the following on WSL2 on Windows 11, using the Debian distro.

Find your download URLs [here](https://archive.synology.com/download/ToolChain)

The instructions should be the same however you'll want to pull the correct linux kernel source for your NAS depending on which kernel version you're currently running, and for the appropriate architecture (The below was done for x86. Different options may be needed on `make` commands for compiling for a different `ARCH` )

#### 1. Install packages for running a kernel build:

```
sudo apt install build-essential \
                  ncurses-dev \
                  bc \
                  libssl-dev \
                  libc6-i386 \
                  curl \
                  libproc-processtable-perl \
                  wget \
                  kmod
```

#### 2. You will need a build folder that exists on an ext4 partition (not NTFS or FAT)

- `mkdir /volume1`
- `mkdir /volume1/synology-toolkit`
- `mkdir /volume1/synology-toolkit/toolchains`
- `cd /volume1/synology-toolkit`

#### 3. Clone the toolkit repo and checkout the DSM version

- `git clone https://github.com/SynologyOpenSource/pkgscripts-ng`
- `cd pkgscripts-ng`
- `git checkout DSM7.2`

#### 4. Create the chroot for your target

- `sudo ./EnvDeploy -v 7.2 -p apollolake`

#### 5. Download and install the toolchain for your platform

- `cd /volume1/synology-toolkit/toolchains`
- `wget --content-disposition https://global.synologydownload.com/download/ToolChain/toolchain/7.2-72746/Intel%20x86%20Linux%204.4.180%20%28Apollolake%29/apollolake-gcc1220_glibc236_x86_64-GPL.txz` (find the URL for your platform)
- `sudo tar xJf apollolake-gcc1220_glibc236_x86_64-GPL.txz -C /usr/local/`

#### 6. Download and install the kernel source for your platform

- `cd /volume1/synology-toolkit`
- `wget --content-disposition https://global.synologydownload.com/download/ToolChain/Synology%20NAS%20GPL%20Source/7.2-64570/apollolake/linux-4.4.x.txz`
- `sudo tar -Jxvf ./linux-4.4.x.txz -C /usr/local/x86_64-pc-linux-gnu/`

#### 7. Change to the kernel source folder (change the folder name with your kernel version):

- `cd /usr/local/x86_64-pc-linux-gnu/linux-4.4.x`

#### 8. Copy the kernel config for your device / platform to .config in the kernel folder. The below example is for apollolake:

- `sudo cp synoconfigs/apollolake .config`

#### 9. Edit the file `Makefile` in the kernel source folder, editing the EXTRAVERSTION to add the plus so that the kernel matches the `uname -r` output on the NAS you're compiling for, and editing the `CROSS_COMPILE` and `ARCH` lines.

- `EXTRAVERSION = +`
- `ARCH            ?= x86_64`
- `CROSS_COMPILE   ?= /usr/local/x86_64-pc-linux-gnu/bin/x86_64-pc-linux-gnu-`

#### 10. Edit the `.config` file you copied, change modules you want to compile as modules to have `=m` if they were previously `is not set`:

- `CONFIG_IP_NF_RAW=m`
- `CONFIG_IP6_NF_RAW=m`

#### 11. Modify the config based on the source:

- `sudo make oldconfig` This will prompt you to choose how to build the added modules (just hit ENTER to accept the defaults)

#### 12. Run the following commands:

- `sudo make prepare`
- `sudo make modules_prepare`

#### 13. Build the modules you're wanting to build (example):

- `sudo make M=net/ipv4/netfilter modules`
- `sudo make M=net/ipv6/netfilter modules`
- (alternatively just build all modules) `sudo make modules`

#### 14. Your modules should now be available in the appropriate folders for copying to your synology. Given the above, they're in:

- `net/ipv4/netfilter/iptable_raw.ko`
- `net/ipv6/netfilter/iptable_raw.ko`

#### 15. You can check the details of the mod by running, for example:

- `sudo modinfo net/ipv4/netfilter/iptable_raw.ko` - The `vermagic` line has to match the kernel version of your NAS precisely (including the `+` suffix):

```
filename:       net/ipv4/netfilter/iptable_raw.ko
license:        GPL
depends:        ip_tables
retpoline:      Y
vermagic:       4.4.302+ SMP mod_unload
```

#### 16. You can now copy these files to your NAS in `/lib/modules`

#### 17. Change the permissions and ownership of the new `.ko` files on the NAS:

```
sudo chown root:root /lib/modules/{iptable_raw.ko,ip6table_raw.ko}
sudo chmod 644 /lib/modules/{iptable_raw.ko,ip6table_raw.ko}
```

#### 18. Load the modules:

```
sudo insmod /lib/modules/ip6table_raw.ko
sudo insmod /lib/modules/iptable_raw.ko
```

#### 19. Assuming you received no errors, validate they're loaded:

```
$ sudo lsmod | grep raw
iptable_raw             1452  0
ip6table_raw            1456  0
ip6_tables             14933  14 ip6table_filter,ip6table_raw
ip_tables              14342  4 iptable_filter,iptable_mangle,iptable_nat,iptable_raw
x_tables               17395  24 ip6table_filter,xt_ipvs,xt_iprange,xt_mark,xt_recent,ip_tables,xt_tcpudp,ipt_MASQUERADE,xt_geoip,xt_limit,xt_state,xt_conntrack,xt_LOG,xt_mac,xt_nat,xt_set,xt_multiport,iptable_filter,ip6table_raw,xt_REDIRECT,iptable_mangle,ip6_tables,xt_addrtype,iptable_raw
```

#### 20. If you want to load the libraries on startup, add the `insmod` lines from above to a Scheduled Task, running as `root` on boot.
