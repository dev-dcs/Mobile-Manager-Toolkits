# curl + mbedtls. Android has no /etc/resolv.conf, so fb calls it with --doh-url
deps="mbedtls zlib brotli zstd"
provides="curl"

build() {
	auto_build --with-mbedtls="$PREFIX" --with-zlib="$PREFIX" --with-brotli="$PREFIX" \
		--with-zstd="$PREFIX" --without-libpsl --without-libidn2 --without-nghttp2 \
		--without-libssh2 --disable-ldap --disable-docs --disable-manual \
		--with-ca-path=/apex/com.android.conscrypt/cacerts --without-ca-bundle
	# install libcurl (lib, headers, libcurl.pc) so libtatsu/libimobiledevice
	# can link it, as well as shipping the CLI
	make -C "$BLD" install >/dev/null
	put_bin "$BLD/src/curl"
	put_license COPYING
}
