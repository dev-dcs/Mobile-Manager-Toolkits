# SoC BootROM dumps - data only, shipped under share/
deps=""
provides=""

build() {
	for d in qualcomm samsung mediatek; do
		[ -d "$d" ] || continue
		for f in "$d"/*.bin; do
			[ -f "$f" ] && put_asset "$f" "bootroms/$f"
		done
	done
}
