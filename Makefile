CORE ?= ux600fd

ifeq ($(CORE),ux600fd)
ISA ?= rv64gc
ABI ?= lp64d
else
ISA ?= rv64imac
ABI ?= lp64
endif

srcdir := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))
srcdir := $(srcdir:/=)
confdir := $(srcdir)/conf
wrkdir := $(CURDIR)/work

buildroot_srcdir := $(srcdir)/buildroot
buildroot_initramfs_wrkdir := $(wrkdir)/buildroot_initramfs

RISCV ?= $(buildroot_initramfs_wrkdir)/host
RVPATH := $(RISCV)/bin:$(PATH)

platform_dts := $(confdir)/nuclei_$(CORE).dts
platform_dtb := $(wrkdir)/nuclei_$(CORE).dtb
platform_sim_dts := $(confdir)/nuclei_$(CORE)_sim.dts
platform_sim_dtb := $(wrkdir)/nuclei_$(CORE)_sim.dtb

platform_openocd_cfg := $(confdir)/openocd_fsl.cfg

target := riscv-nuclei-linux-gnu
CROSS_COMPILE := $(RISCV)/bin/$(target)-
buildroot_initramfs_config := $(confdir)/buildroot_initramfs_$(CORE)_config

buildroot_initramfs_tar := $(buildroot_initramfs_wrkdir)/images/rootfs.tar
buildroot_initramfs_sysroot_stamp := $(wrkdir)/.buildroot_initramfs_sysroot
buildroot_initramfs_sysroot := $(wrkdir)/buildroot_initramfs_sysroot

linux_srcdir := $(srcdir)/linux
linux_wrkdir := $(wrkdir)/linux
linux_defconfig := $(confdir)/linux_$(CORE)_defconfig
linux_gen_initramfs=$(linux_srcdir)/usr/gen_initramfs.sh

vmlinux := $(linux_wrkdir)/vmlinux
linux_image := $(linux_wrkdir)/arch/riscv/boot/Image
vmlinux_stripped := $(linux_wrkdir)/vmlinux-stripped
vmlinux_bin := $(wrkdir)/vmlinux.bin

initramfs := $(wrkdir)/initramfs.cpio.gz

opensbi_srcdir := $(srcdir)/opensbi
opensbi_wrkdir := $(wrkdir)/opensbi
opensbi_payload := $(opensbi_wrkdir)/platform/nuclei/ux600/firmware/fw_payload.elf
opensbi_jumpbin := $(opensbi_wrkdir)/platform/nuclei/ux600/firmware/fw_jump.bin

freeloader_srcdir := $(srcdir)/freeloader
freeloader_wrkdir := $(srcdir)/freeloader
freeloader_elf := $(freeloader_wrkdir)/freeloader.elf

uboot_srcdir := $(srcdir)/u-boot
uboot_wrkdir := $(wrkdir)/u-boot
uboot_bin := $(uboot_wrkdir)/u-boot.bin
uboot_dtb := $(uboot_wrkdir)/u-boot.dtb
uboot_mkimage := $(uboot_wrkdir)/tools/mkimage

uboot_cmd := $(confdir)/uboot.cmd

# Directory for boot images stored in sdcard
boot_wrkdir := $(wrkdir)/boot
boot_zip := $(wrkdir)/boot.zip
boot_ubootscr := $(boot_wrkdir)/boot.scr
boot_image := $(boot_wrkdir)/Image.lz4
boot_uimage_lz4 := $(boot_wrkdir)/uImage.lz4
boot_uinitrd_lz4 := $(boot_wrkdir)/uInitrd.lz4
boot_kernel_dtb := $(boot_wrkdir)/kernel.dtb

# xlspike is prebuilt and installed to PATH
xlspike := xl_spike

# openocd is prebuilt and installed to PATH
openocd := openocd

target_gcc := $(CROSS_COMPILE)gcc
target_gdb := $(CROSS_COMPILE)gdb

.PHONY: all help
all: help

help:
	@echo "Here is a list of make targets supported"
	@echo ""
	@echo "- buildroot_initramfs-menuconfig : run menuconfig for buildroot, configuration will be saved into conf/"
	@echo "- buildroot_initramfs_sysroot : generate rootfs directory using buildroot"
	@echo "- linux-menuconfig : run menuconfig for linux kernel, configuration will be saved into conf/"
	@echo "- buildroot_busybox-menuconfig : run menuconfig for busybox in buildroot"
	@echo "- uboot-menuconfig : run menuconfig for uboot"
	@echo "- initrd : generate initramfs cpio file"
	@echo "- bootimages : generate boot images for SDCard"
	@echo "- freeloader : generate freeloader(first stage loader) run in norflash"
	@echo "- freeloader4m : generate freeloader(first stage loader) 4MB version run in norflash"
	@echo "- upload_freeloader : upload freeloader into development board using openocd and gdb"
	@echo "- uboot : build uboot and generate uboot binary"
	@echo "- sim : run opensbi + linux payload in simulation using xl_spike"
	@echo "- clean : clean this full workspace"
	@echo "- cleanboot : clean generated boot images"
	@echo "- cleanlinux : clean linux workspace"
	@echo "- cleanbuildroot : clean buildroot workspace"
	@echo "- cleansysroot : clean buildroot sysroot files"
	@echo "- cleanuboot : clean u-boot workspace"
	@echo "- cleanfreeloader : clean freeloader generated objects"
	@echo "- cleanopensbi : clean opensbi workspace"
	@echo "- preboot : If you run sim target before, and want to change to bootimages target, run this to prepare environment"
	@echo "- presim : If you run bootimages target before, and want to change to sim target, run this to prepare environment"
	@echo ""
	@echo "Main targets used frequently depending on your user case"
	@echo "If you want to run linux on development board, please run preboot, freeloader, bootimages targets"
	@echo "If you want to run linux in simulation, please run presim, sim targets"


$(target_gcc): buildroot_initramfs_sysroot

$(buildroot_initramfs_wrkdir)/.config: $(buildroot_srcdir)
	rm -rf $(dir $@)
	mkdir -p $(dir $@)
	cp $(buildroot_initramfs_config) $@
	$(MAKE) -C $< RISCV=$(RISCV) O=$(buildroot_initramfs_wrkdir) olddefconfig 

# buildroot_initramfs provides gcc
$(buildroot_initramfs_tar): $(buildroot_srcdir) $(buildroot_initramfs_wrkdir)/.config $(buildroot_initramfs_config)
	$(MAKE) -C $< RISCV=$(RISCV) O=$(buildroot_initramfs_wrkdir)

.PHONY: buildroot_initramfs-menuconfig
buildroot_initramfs-menuconfig: $(buildroot_initramfs_wrkdir)/.config $(buildroot_srcdir)
	$(MAKE) -C $(dir $<) O=$(buildroot_initramfs_wrkdir) menuconfig
	$(MAKE) -C $(dir $<) O=$(buildroot_initramfs_wrkdir) savedefconfig
	cp $(dir $<)/defconfig $(buildroot_initramfs_config)

.PHONY: buildroot_busybox-menuconfig
buildroot_busybox-menuconfig: $(buildroot_initramfs_wrkdir)/.config $(buildroot_srcdir)
	$(MAKE) -C $(dir $<) O=$(buildroot_initramfs_wrkdir) busybox-menuconfig

$(buildroot_initramfs_sysroot_stamp): $(buildroot_initramfs_tar)
	mkdir -p $(buildroot_initramfs_sysroot)
	tar -xpf $< -C $(buildroot_initramfs_sysroot) --exclude ./dev --exclude ./usr/share/locale
	touch $@

$(linux_wrkdir)/.config: $(linux_defconfig) $(linux_srcdir) $(target_gcc)
	mkdir -p $(dir $@)
	cp -p $< $@
	$(MAKE) -C $(linux_srcdir) O=$(linux_wrkdir) ARCH=riscv olddefconfig
ifeq (,$(filter rv%c,$(ISA)))
	sed 's/^.*CONFIG_RISCV_ISA_C.*$$/CONFIG_RISCV_ISA_C=n/' -i $@
	$(MAKE) -C $(linux_srcdir) O=$(linux_wrkdir) ARCH=riscv olddefconfig
endif
ifeq ($(ISA),$(filter rv32%,$(ISA)))
	sed 's/^.*CONFIG_ARCH_RV32I.*$$/CONFIG_ARCH_RV32I=y/' -i $@
	sed 's/^.*CONFIG_ARCH_RV64I.*$$/CONFIG_ARCH_RV64I=n/' -i $@
	$(MAKE) -C $(linux_srcdir) O=$(linux_wrkdir) ARCH=riscv olddefconfig
endif

$(vmlinux): $(linux_srcdir) $(linux_wrkdir)/.config
	$(MAKE) -C $< O=$(linux_wrkdir) \
		CONFIG_INITRAMFS_SOURCE="$(confdir)/initramfs.txt $(buildroot_initramfs_sysroot)" \
		CONFIG_INITRAMFS_ROOT_UID=$(shell id -u) \
		CONFIG_INITRAMFS_ROOT_GID=$(shell id -g) \
		ARCH=riscv \
		CROSS_COMPILE=$(CROSS_COMPILE) \
		PATH=$(RVPATH) \
		vmlinux

$(linux_image): $(linux_srcdir) $(linux_wrkdir)/.config
	$(MAKE) -C $< O=$(linux_wrkdir) \
		CONFIG_INITRAMFS_ROOT_UID=$(shell id -u) \
		CONFIG_INITRAMFS_ROOT_GID=$(shell id -g) \
		ARCH=riscv \
		CROSS_COMPILE=$(CROSS_COMPILE) \
		PATH=$(RVPATH) \
		Image

.PHONY: initrd
initrd: $(initramfs)
	@echo "initramfs cpio file is generated into $<"

$(initramfs): $(buildroot_initramfs_sysroot) $(linux_image)
	cd $(linux_wrkdir) && \
		$(linux_gen_initramfs) \
		-o $@ -u $(shell id -u) -g $(shell id -g) \
		$(confdir)/initramfs.txt \
		$(buildroot_initramfs_sysroot)

$(vmlinux_stripped): $(vmlinux)
	PATH=$(RVPATH) $(target)-strip -o $@ $<

$(vmlinux_bin): $(vmlinux)
	PATH=$(RVPATH) $(target)-objcopy -O binary $< $@

.PHONY: linux-menuconfig
linux-menuconfig: $(linux_wrkdir)/.config
	$(MAKE) -C $(linux_srcdir) O=$(dir $<) ARCH=riscv menuconfig
	$(MAKE) -C $(linux_srcdir) O=$(dir $<) ARCH=riscv savedefconfig
	cp $(dir $<)/defconfig $(linux_defconfig)

$(platform_dtb) : $(platform_dts)
	dtc -O dtb -o $(platform_dtb) $(platform_dts)

$(platform_sim_dtb) : $(platform_sim_dts)
	dtc -O dtb -o $(platform_sim_dtb) $(platform_sim_dts)

$(opensbi_jumpbin):
	rm -rf $(opensbi_wrkdir)
	$(MAKE) -C $(opensbi_srcdir) O=$(opensbi_wrkdir) CROSS_COMPILE=$(CROSS_COMPILE) \
		PLATFORM_RISCV_ABI=$(ABI) PLATFORM_RISCV_ISA=$(ISA) \
		PLATFORM=nuclei/ux600

$(opensbi_payload): $(opensbi_srcdir) $(vmlinux_bin) $(platform_sim_dtb)
	rm -rf $(opensbi_wrkdir)
	mkdir -p $(opensbi_wrkdir)
	$(MAKE) -C $(opensbi_srcdir) O=$(opensbi_wrkdir) CROSS_COMPILE=$(CROSS_COMPILE) \
		PLATFORM_RISCV_ABI=$(ABI) PLATFORM_RISCV_ISA=$(ISA) \
		PLATFORM=nuclei/ux600 FW_PAYLOAD_PATH=$(vmlinux_bin) FW_PAYLOAD_FDT_PATH=$(platform_sim_dtb)

$(buildroot_initramfs_sysroot): $(buildroot_initramfs_sysroot_stamp)

.PHONY: buildroot_initramfs_sysroot vmlinux
buildroot_initramfs_sysroot: $(buildroot_initramfs_sysroot)
vmlinux: $(vmlinux)

.PHONY: bootimages
bootimages: $(boot_zip)
	@echo "SDCard boot images are generated into $(boot_zip) and $(boot_wrkdir)"
	@echo "You can extract the $(boot_zip) to SDCard and insert the SDCard back to board"
	@echo "If freeloader is already flashed to board's norflash, then you can reset power of the board"
	@echo "Then you can open UART terminal with baudrate 57600, you will be able to see kernel boot message"

$(boot_wrkdir):
	mkdir -p $@

$(boot_ubootscr): $(uboot_cmd) $(uboot_mkimage)
	$(uboot_mkimage) -A riscv -T script -O linux -C none -a 0 -e 0 -n "bootscript" -d $(uboot_cmd) $@

$(boot_uimage_lz4): $(linux_image)
	lz4 $< $(boot_image) -f -2
	$(uboot_mkimage) -A riscv -O linux -T kernel -C lz4 -a 0x41200000 -e 0x41200000 -n Linux -d $(boot_image) $@
	rm -f $(boot_image)

$(boot_uinitrd_lz4): $(initramfs)
	lz4 $(initramfs) $(initramfs).lz4 -f -2 -l
	$(uboot_mkimage) -A riscv -T ramdisk -C lz4 -n Initrd -d $(initramfs).lz4 $(boot_uinitrd_lz4)

$(boot_kernel_dtb): $(platform_dts)
	dtc -O dtb -o $(boot_kernel_dtb) $(platform_dts)

$(boot_zip): $(boot_wrkdir) $(boot_ubootscr) $(boot_uimage_lz4) $(boot_uinitrd_lz4) $(boot_kernel_dtb)
	rm -f $(boot_zip)
	cd $(boot_wrkdir) && zip -q -r $(boot_zip) .

.PHONY: uboot
uboot: $(uboot_bin)
	@echo "Uboot binary is generated into $<"

$(uboot_wrkdir)/.config: $(uboot_srcdir) $(target_gcc)
	mkdir -p $(uboot_wrkdir)
	make -C $(uboot_srcdir) O=$(uboot_wrkdir) CROSS_COMPILE=$(CROSS_COMPILE) nuclei_hbird_defconfig

.PHONY: uboot-menuconfig
uboot-menuconfig: $(uboot_wrkdir)/.config
	make -C $(uboot_srcdir) O=$(uboot_wrkdir) CROSS_COMPILE=$(CROSS_COMPILE) menuconfig

$(uboot_dtb): $(uboot_bin)
$(uboot_mkimage) $(uboot_bin): $(uboot_srcdir) $(uboot_wrkdir)/.config
	make -C $(uboot_srcdir) O=$(uboot_wrkdir) CROSS_COMPILE=$(CROSS_COMPILE) all

.PHONY: freeloader prepare4m freeloader4m

prepare4m: buildroot_initramfs_sysroot
	find $(buildroot_initramfs_wrkdir)/build/ -type f -wholename "*busybox*/.config" | xargs sed -i '/CONFIG_STATIC/cCONFIG_STATIC=y'
	rm -rf $(buildroot_initramfs_wrkdir)/images/*
	rm -rf $(buildroot_initramfs_sysroot) $(buildroot_initramfs_sysroot_stamp)
	$(MAKE) -C $(buildroot_srcdir) O=$(buildroot_initramfs_wrkdir) busybox-rebuild
	$(MAKE) CORE=$(CORE) buildroot_initramfs_sysroot
	sed -i '/sbin\/getty/cconsole::respawn:/bin/sh' $(buildroot_initramfs_sysroot)/etc/inittab
	#sed -i '/init\.d/d' $(buildroot_initramfs_sysroot)/etc/inittab
	rm -rf $(buildroot_initramfs_sysroot)/lib/*
	$(MAKE) CORE=$(CORE) cleanboot bootimages

freeloader4m: prepare4m $(freeloader_elf)
	@echo "freeloader is generated in $(freeloader_elf)"
	@echo "You can download this elf into development board using make upload_freeloader"
	@echo "or using openocd and gdb to achieve it"
	@echo "File size of freeloader is as below:"
	size $(freeloader_elf)
	ls -lh $(freeloader_elf)

freeloader: $(freeloader_elf)
	@echo "freeloader is generated in $(freeloader_elf)"
	@echo "You can download this elf into development board using make upload_freeloader"
	@echo "or using openocd and gdb to achieve it"

$(freeloader_elf): $(freeloader_srcdir) $(uboot_bin) $(opensbi_jumpbin) $(boot_zip) $(platform_dtb)
	make -C $(freeloader_srcdir) ARCH=$(ISA) ABI=$(ABI) CROSS_COMPILE=$(CROSS_COMPILE) \
		FW_JUMP_BIN=$(opensbi_jumpbin) UBOOT_BIN=$(uboot_bin) DTB=$(platform_dtb)

upload_freeloader: $(freeloader_elf)
	$(target_gdb) $< -ex "set remotetimeout 240" \
	-ex "target remote | $(openocd) --pipe -f $(platform_openocd_cfg)" \
	--batch -ex "monitor reset halt" -ex "monitor halt" \
	-ex "monitor flash protect 0 0 last off" -ex "load" \
	-ex "monitor resume" -ex "quit"

debug_freeloader: $(freeloader_elf)
	$(target_gdb) $< -ex "set remotetimeout 240" \
	-ex "target remote | $(openocd) --pipe -f $(platform_openocd_cfg)"

.PHONY: clean cleanboot cleanlinux cleanbuildroot cleansysroot cleanfreeloader cleanopensbi prepare presim preboot
clean: cleanfreeloader
	rm -rf $(wrkdir)

cleanboot:
	rm -rf $(boot_wrkdir) $(boot_zip) $(initramfs) $(initramfs).lz4

cleanlinux:
	rm -rf $(linux_wrkdir) $(vmlinux_bin)

cleanbuildroot:
	rm -rf $(buildroot_initramfs_wrkdir)

cleansysroot:
	rm -rf $(buildroot_initramfs_sysroot) $(buildroot_initramfs_sysroot_stamp)

cleanuboot:
	rm -rf $(uboot_wrkdir)

cleanfreeloader:
	make -C $(freeloader_srcdir) clean

cleanopensbi:
	rm -rf $(opensbi_wrkdir)

# If you change your make target from bootimages to sim, you need to run presim first
presim: prepare
# If you change your make target from sim to bootimages, you need to run preboot first
preboot: prepare

prepare:
	rm -rf $(vmlinux_bin) $(vmlinux) $(linux_image)

.PHONY: sim opensbi_sim

opensbi_sim: $(opensbi_payload)

sim: $(opensbi_payload)
	$(xlspike) --isa=$(ISA) $(opensbi_payload)

