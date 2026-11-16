# crypto++ (cryptopp) - static library only, for odin4
deps=""

build() {
	# cross: feed our compiler and flags, keep cryptopp from probing the host CPU
	# -fPIC: the lib is linked into PIE executables (odin4); without it some
	# of cryptopp's static tables emit R_AARCH64_ABS64 relocs that lld rejects
	make -f GNUmakefile -j"$JOBS" static \
		CXX="$CXX" AR="$AR" RANLIB="$RANLIB" \
		CXXFLAGS="$CXXFLAGS -fPIC -DNDEBUG -DCRYPTOPP_DISABLE_ASM" \
		IS_X86=0 IS_X64=0 IS_ARM64=1 >/dev/null
	make -f GNUmakefile install-lib PREFIX="$PREFIX" >/dev/null
	# cryptopp installs a cryptopp.pc? no - drop a minimal one for pkg-config users
	mkdir -p "$PREFIX/lib/pkgconfig"
	cat > "$PREFIX/lib/pkgconfig/libcrypto++.pc" <<PC
prefix=$PREFIX
libdir=\${prefix}/lib
includedir=\${prefix}/include
Name: libcrypto++
Description: Crypto++
Version: 8.9.0
Libs: -L\${libdir} -lcryptopp
Cflags: -I\${includedir}
PC
	cp "$PREFIX/lib/pkgconfig/libcrypto++.pc" "$PREFIX/lib/pkgconfig/libcryptopp.pc"
}
