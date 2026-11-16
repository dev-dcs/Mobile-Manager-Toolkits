# libgeneral - tihmstar's base library (img4tool, img3tool depend on it)
# deep=1: its version is `git rev-list --count HEAD`, dependents gate on >= 92
deps=""
provides=""
deep=1

build() {
	auto_build
	make -C "$BLD" install >/dev/null
}
