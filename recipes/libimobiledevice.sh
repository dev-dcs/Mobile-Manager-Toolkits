# libimobiledevice - iOS communication library + CLI tools
deps="libplist limd-glue libusbmuxd libtatsu openssl"
provides="ideviceinfo idevicepair idevicesyslog idevice_id idevicebackup2 ideviceprovision idevicescreenshot idevicediagnostics idevicecrashreport"

build() {
	auto_build --without-cython
	make -C "$BLD" install >/dev/null
	# ship every idevice* tool this build produced (statically linked, no .libs/)
	for f in "$BLD"/tools/idevice*; do
		[ -f "$f" ] && [ -x "$f" ] && put_bin "$f"
	done
	put_license COPYING COPYING.LESSER
}
