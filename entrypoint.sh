#!/bin/sh

# Check for platform ENV variable
if [ -z "$PLATFORM" ]; then
  echo "Error: PLATFORM is not set!"
  echo "Use one of the following platforms:"
  echo
  jq -r 'keys[]' platforms.json
  exit 1
fi

# Check for config modification file
if [ ! -f "config_modification.json" ]; then
  echo "Error: config_modification.json not found!"
  exit 1
fi

# Check for platforms file
if [ ! -f "platforms.json" ]; then
  echo "Error: platforms.json not found!"
  exit 1
fi

echo "PLATFORM is set to: $PLATFORM"

# read all the values from the platforms file.
export $(jq -r --arg PLATFORM "$PLATFORM" '.[$PLATFORM] | to_entries | map("SYNO_\(.key)=\(.value)") | .[]' platforms.json)


# check we're running the correct image
if [ "$SYNO_VERSION" = "3" ]; then
    if [ "$IMAGE_TYPE" = "standard" ]; then
        echo
        echo "Running on [$IMAGE_TYPE] Docker Image"
        echo "Error: You need to use the LEGACY docker image for compiling on 3.x kernels"
        echo "re-build the image using the Dockerfile_legacy Dockerfile."
        echo "  docker build --no-cache -t compile_legacy_modules -f ./Dockerfile_legacy . "
        echo
        echo "then compile with the compile_legacy_modules image instead"
        echo
        exit 1
    fi
elif [ "$IMAGE_TYPE" = "legacy" ]; then
         echo
         echo "Running on [$IMAGE_TYPE] Docker Image"
         echo "Error: You need to use the STANDARD docker image for compiling on kernels other than 3.x"
         echo "re-build the image using the regular Dockerfile."
         echo "  docker build --no-cache -t compile_modules . "
         echo
         echo "then compile with the compile_modules image instead"
         echo
         exit 1
fi

#------------------------------------------------------

echo
echo "Setup toolkit..."
echo
git clone https://github.com/SynologyOpenSource/pkgscripts-ng
cd pkgscripts-ng
git checkout DSM7.3
./EnvDeploy -v 7.3 -p $PLATFORM
cd ..

#------------------------------------------------------

echo
echo "Downloads..."
echo
#download toolkit
echo "Downloading toolchain for $PLATFORM"
toolchain_fn=$(basename "$SYNO_toolchain")
curl --progress-bar -L -o "$toolchain_fn" "$SYNO_toolchain"
toolchain_folder=$(tar -Jtf "${toolchain_fn}" | cut -d/ -f1 | uniq | head -n 1)
echo "Downloaded toolchain: $toolchain_fn"
echo "Archive top-level folder name: $toolchain_folder"

#download kernel
echo "Downloading kernel source for $PLATFORM"
kernel_fn=$(basename "$SYNO_kernel")
curl --progress-bar -L -o "$kernel_fn" "$SYNO_kernel"
kernel_folder=$(tar -Jtf "${kernel_fn}" | cut -d/ -f1 | uniq | head -n 1)
echo "Downloaded kernel source: $kernel_fn"
echo "Archive top-level-folder name: $kernel_folder"


#------------------------------------------------------

echo
echo "Installs..."
echo
# install toolchain
tar -Jxvf ./${toolchain_fn} -C /usr/local/

# install kernel
tar -Jxvf ./${kernel_fn} -C /usr/local/$toolchain_folder/

#------------------------------------------------------

echo
echo "Configure Build..."
echo

# copy the kernel config for the platform
echo "Moving $PLATFORM config to .config"

if [ "$SYNO_VERSION" = "5" ]; then
	echo "copying config for Kernel v5.x..."
	cd /usr/local/$toolchain_folder/$kernel_folder
	cp synology/synoconfigs/$PLATFORM .config
else
	echo "copying config for Kernel v4 or below..."
	cd /usr/local/$toolchain_folder/$kernel_folder
	cp synoconfigs/$PLATFORM .config
fi

if [ "$SYNO_VERSION" = "3" ]; then
    echo "Using Synology cross toolchain for Linux 3.x"

    export CROSS_COMPILE="$SYNO_CROSS_COMPILE"
    export ARCH="$SYNO_ARCH"

    # Ensure kernel uses cross compiler
    export CC="${CROSS_COMPILE}gcc"

    # avoid PLT relocations on gcc12
    export KCFLAGS="-fno-plt -fno-pic -fno-pie -mcmodel=kernel -mno-red-zone -fno-stack-protector"
    export HOSTCFLAGS="-fno-plt -fno-pie"

    sed -i 's/CONFIG_RETPOLINE=y/CONFIG_RETPOLINE=n/' .config || true
fi


echo "Modifying Makefile"
#replace values in Makefile
echo " version: $SYNO_VERSION"
sed -i "s/^VERSION.*/VERSION = $SYNO_VERSION/" Makefile
echo " patchlevel: $SYNO_PATCHLEVEL"
sed -i "s/^PATCHLEVEL.*/PATCHLEVEL = $SYNO_PATCHLEVEL/" Makefile
echo " sublevel: $SYNO_SUBLEVEL"
sed -i "s/^SUBLEVEL.*/SUBLEVEL = $SYNO_SUBLEVEL/" Makefile
echo " EXTRAVERSION: $SYNO_EXTRAVERSION"
sed -i "s/^EXTRAVERSION.*/EXTRAVERSION = $SYNO_EXTRAVERSION/" Makefile
echo " ARCH : $SYNO_ARCH"
sed -i "s/^ARCH.*/ARCH := $SYNO_ARCH/" Makefile
echo " CROSS_COMPILE: $SYNO_CROSS_COMPILE"
escaped_cc=$(printf '%s\n' "$SYNO_CROSS_COMPILE" | sed 's/[\/&]/\\&/g')
sed -i "s/^CROSS_COMPILE.*/CROSS_COMPILE := $escaped_cc/" Makefile

#------------------------------------------------------

echo
echo "Modifying module config"
echo
jq -r 'to_entries[] | "\(.key) \(.value)"' "/synology-toolkit/config_modification.json" | while read -r key value; do

    echo "Modifying $key..."

    # Uncomment or replace if it's in the file already, commented or not
    sed -i "s|[# ].*$key.*|$value|" .config


    # If the setting is not found at all, append it to the file
    if ! grep -q "^$key=" .config; then
        echo "$value" >> .config
    fi
done

#------------------------------------------------------
echo
echo "Running make oldconfig..."
echo

echo "Compiler:"
"${CROSS_COMPILE}gcc" --version || exit 1

yes "" | make oldconfig

#------------------------------------------------------

#------------------------------------------------------
echo
echo "Applying any patching..."
echo

/synology-toolkit/apply_patches.sh

#------------------------------------------------------

echo
echo "Compiling modules..."
echo

make prepare
make modules_prepare
# do not fully compile; generate Module.symvers
# make modules -j$(nproc) KBUILD_MODPOST_NOFINAL=1

# compile the modules needed.
make -j$(nproc) M=net/ipv4/netfilter modules
make -j$(nproc) M=net/ipv6/netfilter modules
make -j$(nproc) M=fs/overlayfs modules

#------------------------------------------------------

FINAL_FOLDER="/compiled_modules/$SYNO_VERSION.$SYNO_PATCHLEVEL.$SYNO_SUBLEVEL$SYNO_EXTRAVERSION/$PLATFORM"
mkdir -p $FINAL_FOLDER
cp net/ipv4/netfilter/iptable_raw.ko $FINAL_FOLDER/iptable_raw.ko
cp net/ipv6/netfilter/ip6table_raw.ko $FINAL_FOLDER/ip6table_raw.ko
cp fs/overlayfs/overlay.ko $FINAL_FOLDER/overlay.ko
cp net/ipv6/netfilter/nf_nat_ipv6.ko $FINAL_FOLDER/nf_nat_ipv6.ko
cp net/ipv6/netfilter/nf_nat_masquerade_ipv6.ko $FINAL_FOLDER/nf_nat_masquerade_ipv6.ko
cp net/ipv6/netfilter/ip6table_nat.ko $FINAL_FOLDER/ip6table_nat.ko
cp net/ipv6/netfilter/ip6t_MASQUERADE.ko $FINAL_FOLDER/ip6t_MASQUERADE.ko

echo "Finished; Copied modules to $FINAL_FOLDER/"
exit 0
