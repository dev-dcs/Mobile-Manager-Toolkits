# shellcheck shell=sh
# elf_maps <file> <page size> - true if every PT_LOAD of a 64-bit ELF can be
# mmapped with that page size. Only needs od, so it runs in the installer too.
# @Dev_DcS

_u() { od -An -t "u$3" -j "$2" -N "$3" "$1" 2>/dev/null | tr -d ' \n'; }

elf_maps() {
	[ "$(head -c 4 "$1" 2>/dev/null | od -An -t x1 | tr -d ' \n')" = 7f454c46 ] || return 2
	[ "$(_u "$1" 4 1)" = 2 ] || return 2
	_ph=$(_u "$1" 32 8) _pe=$(_u "$1" 54 2) _pn=$(_u "$1" 56 2) _i=0
	while [ "$_i" -lt "$_pn" ]; do
		_o=$((_ph + _i * _pe))
		if [ "$(_u "$1" "$_o" 4)" = 1 ]; then
			_off=$(_u "$1" $((_o + 8)) 8) _va=$(_u "$1" $((_o + 16)) 8) _al=$(_u "$1" $((_o + 48)) 8)
			[ $((_al % $2)) -eq 0 ] || return 1
			[ $(((_va - _off) % $2)) -eq 0 ] || return 1
		fi
		_i=$((_i + 1))
	done
	return 0
}
