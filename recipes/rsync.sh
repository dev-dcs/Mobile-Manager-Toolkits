# rsync - sync folders with the workbench, a PC or another phone
deps="zstd lz4"
provides="rsync"

build() {
	auto_build --disable-md2man --disable-xxhash --disable-openssl \
		--with-included-popt --with-included-zlib --disable-acl-support --disable-idn
	put_bin "$BLD/rsync"
	put_license COPYING
}
