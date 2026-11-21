# jq - json from the command line (adb dumps, firmware manifests)
deps=""
provides="jq"

build() {
	auto_build --with-oniguruma=builtin --disable-docs --disable-maintainer-mode
	put_bin "$BLD/jq"
	put_license COPYING
}
