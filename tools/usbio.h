/*
 * usbio.h - bulk in/out on one USB interface through libusb (usbfs),
 * so the tools work without the kernel's serial drivers.
 * Shared by atcmd and qcdiag.  @Dev_DcS
 */
#ifndef USBIO_H
#define USBIO_H

#ifdef HAVE_LIBUSB
#include <libusb.h>
#include <stdio.h>
#include <string.h>

struct usbio {
	libusb_context *ctx;
	libusb_device_handle *h;
	int iface;
	unsigned char in, out;
};

/* "05c6:9008" -> vid/pid, "" or NULL -> any */
static inline int usbio_parse_id(const char *s, int *vid, int *pid)
{
	unsigned v, p;

	*vid = *pid = 0;
	if (!s || !*s)
		return 0;
	if (sscanf(s, "%x:%x", &v, &p) != 2)
		return -1;
	*vid = v;
	*pid = p;
	return 0;
}

static inline int iface_has_bulk(const struct libusb_interface_descriptor *d,
				 unsigned char *in, unsigned char *out)
{
	int i;

	*in = *out = 0;
	for (i = 0; i < d->bNumEndpoints; i++) {
		const struct libusb_endpoint_descriptor *e = &d->endpoint[i];

		if ((e->bmAttributes & 3) != LIBUSB_TRANSFER_TYPE_BULK)
			continue;
		if (e->bEndpointAddress & 0x80) {
			if (!*in)
				*in = e->bEndpointAddress;
		} else if (!*out) {
			*out = e->bEndpointAddress;
		}
	}
	return *in && *out;
}

/*
 * Open the first interface matching the filters. vid/pid 0 = any,
 * cls/sub/proto -1 = any, want_if -1 = any. adb and fastboot interfaces
 * (ff/42/xx) are always skipped.
 */
static inline int usbio_open(struct usbio *u, int vid, int pid, int want_if,
			     int cls, int sub, int proto)
{
	libusb_device **list;
	ssize_t n, i;
	int r, found = 0;

	memset(u, 0, sizeof(*u));
	u->iface = -1;
	if (libusb_init(&u->ctx))
		return -1;
	n = libusb_get_device_list(u->ctx, &list);
	for (i = 0; i < n && !found; i++) {
		struct libusb_device_descriptor dd;
		struct libusb_config_descriptor *cfg;
		int k;

		if (libusb_get_device_descriptor(list[i], &dd))
			continue;
		if (dd.bDeviceClass == LIBUSB_CLASS_HUB)
			continue;
		if ((vid && dd.idVendor != vid) || (pid && dd.idProduct != pid))
			continue;
		if (libusb_get_active_config_descriptor(list[i], &cfg))
			continue;
		for (k = 0; k < cfg->bNumInterfaces && !found; k++) {
			const struct libusb_interface_descriptor *d;

			if (!cfg->interface[k].num_altsetting)
				continue;
			d = &cfg->interface[k].altsetting[0];
			if (d->bInterfaceClass == 0xff && d->bInterfaceSubClass == 0x42)
				continue;
			if (want_if >= 0 && d->bInterfaceNumber != want_if)
				continue;
			if (cls >= 0 && d->bInterfaceClass != cls)
				continue;
			if (sub >= 0 && d->bInterfaceSubClass != sub)
				continue;
			if (proto >= 0 && d->bInterfaceProtocol != proto)
				continue;
			if (!iface_has_bulk(d, &u->in, &u->out))
				continue;
			r = libusb_open(list[i], &u->h);
			if (r) {
				fprintf(stderr, "usb: open %04x:%04x: %s\n", dd.idVendor,
					dd.idProduct, libusb_strerror(r));
				continue;
			}
			u->iface = d->bInterfaceNumber;
			found = 1;
		}
		libusb_free_config_descriptor(cfg);
	}
	libusb_free_device_list(list, 1);

	if (!found) {
		libusb_exit(u->ctx);
		return -1;
	}
	libusb_set_auto_detach_kernel_driver(u->h, 1);
	r = libusb_claim_interface(u->h, u->iface);
	if (r) {
		fprintf(stderr, "usb: claim interface %d: %s\n", u->iface, libusb_strerror(r));
		libusb_close(u->h);
		libusb_exit(u->ctx);
		return -1;
	}
	return 0;
}

static inline int usbio_write(struct usbio *u, const void *buf, int len, int ms)
{
	int done = 0, r;

	r = libusb_bulk_transfer(u->h, u->out, (unsigned char *)buf, len, &done, ms);
	return r ? -1 : done;
}

/* returns bytes read, 0 on timeout, -1 on error */
static inline int usbio_read(struct usbio *u, void *buf, int len, int ms)
{
	int got = 0, r;

	r = libusb_bulk_transfer(u->h, u->in, buf, len, &got, ms);
	if (r == LIBUSB_ERROR_TIMEOUT)
		return got;
	return r ? -1 : got;
}

static inline void usbio_close(struct usbio *u)
{
	if (!u->h)
		return;
	libusb_release_interface(u->h, u->iface);
	libusb_close(u->h);
	libusb_exit(u->ctx);
	u->h = NULL;
}
#endif /* HAVE_LIBUSB */

#endif
