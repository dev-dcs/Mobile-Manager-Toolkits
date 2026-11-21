# patchelf - edit interpreter, rpath and needed libs of ELF files
deps=""
provides="patchelf"

build() {
	auto_build
	put_bin "$BLD/src/patchelf"
	put_license COPYING
}
