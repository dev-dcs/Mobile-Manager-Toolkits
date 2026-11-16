# img4tool - Apple IMG4 / IM4P / IM4M parser and packer (tihmstar)
deps="libgeneral libplist openssl lzfse"
provides="img4tool"
deep=1

build() {
	auto_build --without-libfwkeyfetch
	# statically linked, binary may be in .libs/ or the build dir
	if [ -f "$BLD/img4tool/.libs/img4tool" ]; then
		put_bin "$BLD/img4tool/.libs/img4tool" img4tool
	else
		put_bin "$BLD/img4tool/img4tool" img4tool
	fi
	put_license LICENSE
}
