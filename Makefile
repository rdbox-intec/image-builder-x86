default: build

build:
	cp -rf ../image-builder-raw/rpi-raw.img.zip .
	cp -rf /var/cache/pbuilder/raspbian-stretch-armhf/result/*.deb ./builder/files/tmp/deb-files/
	docker build -t image-builder-rpi .

sd-image: build
	docker run --rm --privileged -v $(shell pwd):/workspace -v /boot:/boot -v /lib/modules:/lib/modules -e CIRCLE_TAG -e VERSION image-builder-rpi

shell: build
	docker run -ti --privileged -v $(shell pwd):/workspace -v /boot:/boot -v /lib/modules:/lib/modules -e CIRCLE_TAG -e VERSION image-builder-rpi bash

test:
	VERSION=dirty docker run --rm -ti --privileged -v $(shell pwd):/workspace -v /boot:/boot -v /lib/modules:/lib/modules -e CIRCLE_TAG -e VERSION image-builder-rpi bash -c "unzip /workspace/hypriotos-rpi-dirty.img.zip && rspec --format documentation --color /workspace/builder/test/*_spec.rb"

shellcheck: build
	VERSION=dirty docker run --rm -ti -v $(shell pwd):/workspace image-builder-rpi bash -c 'shellcheck /workspace/builder/*.sh /workspace/builder/files/var/lib/cloud/scripts/per-once/*'

test-integration: test-integration-image test-integration-docker

test-integration-image:
	docker run --rm -ti -v $(shell pwd)/builder/test-integration:/serverspec:ro -e BOARD uzyexe/serverspec:2.24.3 bash -c "rspec --format documentation --color spec/hypriotos-image"

test-integration-docker:
	docker run --rm -ti -v $(shell pwd)/builder/test-integration:/serverspec:ro -e BOARD uzyexe/serverspec:2.24.3 bash -c "rspec --format documentation --color spec/hypriotos-docker"

tag:
	git tag ${TAG}
	git push origin ${TAG}


clean:
	rm -rf *.log
	rm -rf *.img.zip
	rm -rf *.img.zip.sha256
	rm -rf rootfs-armhf-raspbian-*.tar.gz
	rm -rf rpi-raw.img.zip
	rm -rf builder/files/tmp/deb-files/*

