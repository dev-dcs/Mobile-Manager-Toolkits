/*
 * atcmd - send AT commands to a modem and print the answer.
 *
 *   atcmd -d /dev/ttyACM0 AT+CGMR
 *   atcmd -u 04e8:6860 'AT+DEVCONINFO'      (CDC-ACM over libusb, no tty driver needed)
 *   atcmd -d /dev/smd11                     (no command: one per line from stdin)
 *
 * exit: 0 OK, 1 ERROR, 2 timeout, 3 I/O problem
 * @Dev_DcS
 */
#define _DEFAULT_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

#include "usbio.h"

static int fd = -1;
#ifdef HAVE_LIBUSB
static struct usbio usb;
static int use_usb;
#endif
static int timeout_ms = 3000;
static int quiet_echo = 1;

static long now_ms(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec * 1000L + ts.tv_nsec / 1000000;
}

static speed_t baud(int b)
{
	switch (b) {
	case 9600: return B9600;
	case 19200: return B19200;
	case 38400: return B38400;
	case 57600: return B57600;
	case 230400: return B230400;
	case 460800: return B460800;
	case 921600: return B921600;
	default: return B115200;
	}
}

static int open_tty(const char *path, int b)
{
	struct termios t;

	fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK);
	if (fd < 0) {
		fprintf(stderr, "atcmd: %s: %s\n", path, strerror(errno));
		return -1;
	}
	/* smd nodes and friends have no termios - don't care if this fails */
	if (tcgetattr(fd, &t) == 0) {
		cfmakeraw(&t);
		cfsetispeed(&t, baud(b));
		cfsetospeed(&t, baud(b));
		t.c_cflag |= CLOCAL | CREAD;
		t.c_cc[VMIN] = 0;
		t.c_cc[VTIME] = 0;
		tcsetattr(fd, TCSANOW, &t);
		tcflush(fd, TCIOFLUSH);
	}
	return 0;
}

static int xwrite(const char *s, int len)
{
#ifdef HAVE_LIBUSB
	if (use_usb)
		return usbio_write(&usb, s, len, 1000) == len ? 0 : -1;
#endif
	while (len > 0) {
		ssize_t w = write(fd, s, len);

		if (w < 0) {
			if (errno == EAGAIN || errno == EINTR) {
				usleep(1000);
				continue;
			}
			return -1;
		}
		s += w;
		len -= w;
	}
	return 0;
}

/* -1 error, 0 nothing within ms, >0 bytes */
static int xread(char *buf, int len, int ms)
{
#ifdef HAVE_LIBUSB
	if (use_usb)
		return usbio_read(&usb, buf, len, ms);
#endif
	struct pollfd p = { .fd = fd, .events = POLLIN };
	int r = poll(&p, 1, ms);

	if (r <= 0)
		return r;
	r = read(fd, buf, len);
	if (r < 0 && (errno == EAGAIN || errno == EINTR))
		return 0;
	return r;
}

static int is_final(const char *l)
{
	static const char *const fin[] = {
		"OK", "ERROR", "+CME ERROR", "+CMS ERROR", "NO CARRIER",
		"BUSY", "NO ANSWER", "NO DIALTONE", NULL
	};
	int i;

	for (i = 0; fin[i]; i++)
		if (!strncmp(l, fin[i], strlen(fin[i])))
			return strcmp(l, "OK") ? 1 : 0;
	return -1;
}

static int run(const char *cmd)
{
	char buf[4096], line[4096];
	int ll = 0, res = 2;
	long end;

	/* drop whatever unsolicited output is sitting in the buffer */
	while (xread(buf, sizeof(buf), 50) > 0)
		;
	snprintf(buf, sizeof(buf), "%s\r", cmd);
	if (xwrite(buf, strlen(buf))) {
		perror("atcmd: write");
		return 3;
	}

	end = now_ms() + timeout_ms;
	while (now_ms() < end) {
		int n = xread(buf, sizeof(buf), (int)(end - now_ms()));
		int i;

		if (n < 0) {
			perror("atcmd: read");
			return 3;
		}
		for (i = 0; i < n; i++) {
			char c = buf[i];

			if (c != '\r' && c != '\n') {
				if (ll < (int)sizeof(line) - 1)
					line[ll++] = c;
				continue;
			}
			if (!ll)
				continue;
			line[ll] = 0;
			ll = 0;
			if (quiet_echo && !strcmp(line, cmd))
				continue;
			puts(line);
			res = is_final(line);
			if (res >= 0) {
				fflush(stdout);
				return res;
			}
			res = 2;
		}
	}
	fflush(stdout);
	return 2;
}

static void usage(void)
{
	fputs("usage: atcmd (-d tty | -u [vid:pid]) [-i iface] [-b baud] [-t sec] [-e] [command...]\n"
	      "  -d  serial device (ttyACM, ttyUSB, smd, umts_atc ...)\n"
	      "  -u  CDC-ACM data interface through libusb, optional vid:pid\n"
	      "  -i  USB interface number (default: first CDC data interface)\n"
	      "  -b  baud rate, default 115200 (ignored for usb)\n"
	      "  -t  seconds to wait for OK/ERROR, default 3\n"
	      "  -e  keep the echoed command in the output\n"
	      "without a command, commands are read from stdin, one per line\n", stderr);
}

int main(int argc, char **argv)
{
	const char *dev = NULL, *usbid = NULL;
	int b = 115200, iface = -1, o, res = 0, want_usb = 0;

	(void)iface;

	while ((o = getopt(argc, argv, "d:u::i:b:t:eh")) != -1) {
		switch (o) {
		case 'd': dev = optarg; break;
		case 'u': want_usb = 1; usbid = optarg; break;
		case 'i': iface = atoi(optarg); break;
		case 'b': b = atoi(optarg); break;
		case 't': timeout_ms = atoi(optarg) * 1000; break;
		case 'e': quiet_echo = 0; break;
		default: usage(); return o == 'h' ? 0 : 3;
		}
	}
	/* -u with a separate argument: atcmd -u 04e8:6860 AT */
	if (want_usb && !usbid && optind < argc && strchr(argv[optind], ':') &&
	    strncmp(argv[optind], "AT", 2) && strncmp(argv[optind], "at", 2))
		usbid = argv[optind++];

	if (want_usb) {
#ifdef HAVE_LIBUSB
		int vid, pid;

		if (usbio_parse_id(usbid, &vid, &pid)) {
			fprintf(stderr, "atcmd: bad vid:pid '%s'\n", usbid);
			return 3;
		}
		if (usbio_open(&usb, vid, pid, iface, iface < 0 ? 0x0a : -1, -1, -1)) {
			fprintf(stderr, "atcmd: no CDC data interface found\n");
			return 3;
		}
		use_usb = 1;
#else
		fprintf(stderr, "atcmd: built without libusb\n");
		return 3;
#endif
	} else if (!dev) {
		usage();
		return 3;
	} else if (open_tty(dev, b)) {
		return 3;
	}

	if (optind < argc) {
		for (; optind < argc && res != 3; optind++)
			res = run(argv[optind]);
	} else {
		char l[1024];

		while (fgets(l, sizeof(l), stdin)) {
			l[strcspn(l, "\r\n")] = 0;
			if (!*l)
				continue;
			res = run(l);
			if (res == 3)
				break;
		}
	}

#ifdef HAVE_LIBUSB
	if (use_usb)
		usbio_close(&usb);
#endif
	if (fd >= 0)
		close(fd);
	return res;
}
