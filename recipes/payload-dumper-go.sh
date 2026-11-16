# payload-dumper-go - pulls partitions out of OTA payload.bin
# cgo: liblzma from our xz recipe, zstd comes prebuilt inside gozstd
deps="xz"
provides="payload-dumper-go"

build() {
	CGO_ENABLED=1 GOOS=linux GOARCH=arm64 GOTOOLCHAIN=auto \
	CGO_CFLAGS="-O2 -I$PREFIX/include" CGO_LDFLAGS="-L$PREFIX/lib" \
		go build -trimpath -o payload-dumper-go \
		-ldflags "-s -w -linkmode external -extldflags -static" .
	put_bin payload-dumper-go
	put_license LICENSE
}
