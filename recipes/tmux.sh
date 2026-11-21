# tmux - keeps long jobs (dumps, flashes) alive when the terminal app dies
# no /tmp on Android, so the socket goes to /data/local/tmp
deps="libevent ncurses"
provides="tmux"

build() {
	sed -i 's|"\$TMUX_TMPDIR:" _PATH_TMP|"$TMUX_TMPDIR:/data/local/tmp/"|' tmux.h
	auto_build
	put_bin "$BLD/tmux"
	put_license COPYING
}
