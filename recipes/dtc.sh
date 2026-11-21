# dtc - device tree compiler, plus fdtdump/fdtget/fdtput/fdtoverlay for dtb and dtbo work
deps=""
provides="dtc fdtdump fdtget fdtput fdtoverlay"
hostneeds="flex bison"

build() {
	make -j"$JOBS" CC="$CC" AR="$AR" EXTRA_CFLAGS="$CFLAGS" WARNINGS= LDFLAGS="$LDFLAGS" \
		STATIC_BUILD=1 NO_PYTHON=1 NO_YAML=1 NO_VALGRIND=1 dtc fdtdump fdtget fdtput fdtoverlay
	for b in $provides; do put_bin "$b"; done
	put_license README.license GPL BSD-2-Clause
}
