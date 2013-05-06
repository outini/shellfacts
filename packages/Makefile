PKGTARGETS = apt-package pkgsrc-package
FILES	   = facts.d shellfacts manpages

clean:
	@echo "Cleaning files for each package types"
	cd apt; rm -rf $(FILES)
	cd pkgsrc; rm -rf $(FILES)

clean-all: clean
	@echo "Cleaning generated packages"
	rm -rf shellfacts_*

apt-package:
	@echo "Building APT package"
	for item in $(FILES) ; do cp -R ../$$item apt/ ; done

	cd apt; $(MAKE) package

pkgsrc-package:
	@echo "Build of pkgsrc not implemented yet"

all-packages: $(PKGTARGETS)

all: clean-all all-packages
