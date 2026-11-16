# protobuf 21.x: host protoc for codegen + static libprotobuf for the target
deps=""

build() {
	if ! "$HOSTP/bin/protoc" --version 2>/dev/null | grep -q " ${REF#v}"; then
		say "protobuf: host protoc"
		env -u CC -u CXX -u AR -u RANLIB -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS \
			-u PKG_CONFIG -u PKG_CONFIG_LIBDIR \
			cmake -S . -B "$BLD-host" -G Ninja -DCMAKE_BUILD_TYPE=Release \
			-DCMAKE_INSTALL_PREFIX="$HOSTP" -DCMAKE_CXX_STANDARD=17 \
			-Dprotobuf_BUILD_TESTS=OFF -Dprotobuf_BUILD_SHARED_LIBS=OFF >/dev/null
		ninja -C "$BLD-host" -j "$JOBS" protoc
		install -m 755 "$BLD-host/protoc" "$HOSTP/bin/protoc"
	fi
	cmake_build -DCMAKE_CXX_STANDARD=17 -Dprotobuf_BUILD_TESTS=OFF \
		-Dprotobuf_BUILD_PROTOC_BINARIES=OFF -Dprotobuf_WITH_ZLIB=OFF
	cmake_install
}
