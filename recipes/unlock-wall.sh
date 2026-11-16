# bootloader-unlock-wall-of-shame - markdown DB for fb eng lookup (text only;
# upstream ships marketing videos/images we don't need)
deps=""
provides=""

build() {
	mkdir -p "$OUT/asset/unlock-db/brands"
	# ship only the per-brand markdown, not images/videos/resources
	if [ -d brands ]; then
		for d in brands/*/; do
			b=${d%/}; b=${b##*/}
			[ -f "$d/README.md" ] || continue
			mkdir -p "$OUT/asset/unlock-db/brands/$b"
			cp "$d/README.md" "$OUT/asset/unlock-db/brands/$b/"
		done
	fi
	[ -f README.md ] && cp README.md "$OUT/asset/unlock-db/"
	return 0
}
