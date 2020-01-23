default: build

build:
	docker build -f Dockerfile.circle -t image-builder-x86 .

sd-image: build
	docker run --rm --privileged -v $(shell pwd):/workspace -v /boot:/boot -v /lib/modules:/lib/modules -e CIRCLE_TAG -e VERSION image-builder-x86

shell: build
	docker run -ti --privileged -v $(shell pwd):/workspace -v /boot:/boot -v /lib/modules:/lib/modules -e CIRCLE_TAG -e VERSION image-builder-x86 bash

test:
	VERSION=dirty docker run --rm -ti --privileged -v $(shell pwd):/workspace -v /boot:/boot -v /lib/modules:/lib/modules -e CIRCLE_TAG -e VERSION image-builder-x86 bash -c "unzip /workspace/hypriotos-rpi-dirty.img.zip && rspec --format documentation --color /workspace/builder/test/*_spec.rb"

shellcheck: build
	VERSION=dirty docker run --rm -ti -v $(shell pwd):/workspace image-builder-x86 bash -c 'shellcheck /workspace/builder/*.sh /workspace/builder/files/var/lib/cloud/scripts/per-once/*'

test-integration: test-integration-image test-integration-docker

test-integration-image:
	docker run --rm -ti -v $(shell pwd)/builder/test-integration:/serverspec:ro -e BOARD uzyexe/serverspec:2.24.3 bash -c "rspec --format documentation --color spec/hypriotos-image"

test-integration-docker:
	docker run --rm -ti -v $(shell pwd)/builder/test-integration:/serverspec:ro -e BOARD uzyexe/serverspec:2.24.3 bash -c "rspec --format documentation --color spec/hypriotos-docker"

tag:
	git tag ${TAG}
	git push origin ${TAG}


# RDBOX #################################################
build-local:
	mkdir -p ./builder/files/tmp/deb-files/
	cp -rf ../image-builder-raw/x86-raw.img.zip .
	cp -rf /var/cache/pbuilder/debian-buster-amd64/result/*.deb ./builder/files/tmp/deb-files/
	docker build -t image-builder-x86 .
	
clean:
	rm -rf *.log
	rm -rf *.img
	rm -rf *.img.zip
	rm -rf *.img.zip.sha256
	rm -rf rootfs-armhf-raspbian-*.tar.gz
	rm -rf rpi-raw.img.zip
	rm -rf builder/files/tmp/deb-files/*

usb-image-rdbox-legacy-sata: build
	docker run --rm --privileged -v $(shell pwd):/workspace -v /boot:/boot -v /lib/modules:/lib/modules -e CIRCLE_TAG -e VERSION image-builder-x86 /builder/build.sh rdbox cloud legacy sata

usb-image-rdbox-uefi-sata: build
	docker run --rm --privileged -v $(shell pwd):/workspace -v /boot:/boot -v /lib/modules:/lib/modules -e CIRCLE_TAG -e VERSION image-builder-x86 /builder/build.sh rdbox cloud uefi sata

usb-image-rdbox-local-legacy-sata: build-local
	docker run --rm --privileged -v $(shell pwd):/workspace -v /boot:/boot -v /lib/modules:/lib/modules -e CIRCLE_TAG -e VERSION image-builder-x86 /builder/build.sh rdbox local legacy sata

usb-image-rdbox-local-uefi-sata: build-local
	docker run --rm --privileged -v $(shell pwd):/workspace -v /boot:/boot -v /lib/modules:/lib/modules -e CIRCLE_TAG -e VERSION image-builder-x86 /builder/build.sh rdbox local uefi sata
