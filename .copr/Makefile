# COPR invokes: make -f .copr/Makefile srpm outdir=<dir>
# Runs as root in a Fedora mock chroot with network access.

srpm:
	dnf -y install rpm-build spectool
	mkdir -p sources
	spectool -g -C sources/ msys2-cross.spec
	bash scripts/make-srpm-sources.sh sources/
	rpmbuild -bs msys2-cross.spec \
		--define "_sourcedir $$(pwd)/sources" \
		--define "_srcrpmdir $(outdir)"
