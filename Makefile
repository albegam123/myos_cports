SHELL := /bin/sh
ARCH ?= amd64
OUT ?= $(CURDIR)/out
SOURCE_DATE_EPOCH ?= 0

.PHONY: all doctor bootstrap packages rootfs disk initrd-tools initrd check test clean

all: initrd

doctor:
	@./scripts/doctor.sh

bootstrap:
	@./scripts/bootstrap-cports.sh

packages:
	@SOURCE_DATE_EPOCH=$(SOURCE_DATE_EPOCH) ./scripts/build-packages.sh $(ARCH)

rootfs:
	@SOURCE_DATE_EPOCH=$(SOURCE_DATE_EPOCH) ./scripts/mkrootfs.sh $(ARCH) "$(OUT)"

disk:
	@SOURCE_DATE_EPOCH=$(SOURCE_DATE_EPOCH) ./scripts/mkrootfs-image.sh $(ARCH) "$(OUT)"

initrd-tools:
	@SOURCE_DATE_EPOCH=$(SOURCE_DATE_EPOCH) ./scripts/build-initrd-tools.sh $(ARCH) "$(OUT)"

initrd: initrd-tools
	@SOURCE_DATE_EPOCH=$(SOURCE_DATE_EPOCH) ./scripts/mkinitrd.sh $(ARCH) "$(OUT)"

check:
	@./scripts/check.sh

test: check
	@true

clean:
	@rm -rf "$(OUT)"
