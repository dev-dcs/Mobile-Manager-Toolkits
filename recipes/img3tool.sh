# img3tool - Apple IMG3 (old 32-bit format) parser (tihmstar)
deps="libgeneral libplist openssl"
provides="img3tool"
deep=1

build() {
	auto_build --without-libfwkeyfetch 2>/dev/null || auto_build
	put_bin "$BLD/img3tool/img3tool" img3tool
	put_license LICENSE
}
