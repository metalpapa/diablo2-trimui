.PHONY: backup build copy update

backup:
	bash scripts/backup-trimui.sh

build:
	bash scripts/build-trimui-package.sh

copy:
	bash scripts/copy-trimui-to-sd.sh

update:
	bash scripts/build-trimui-package.sh
	bash scripts/copy-trimui-to-sd.sh