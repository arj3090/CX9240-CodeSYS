// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Manufacturing Automation, LLC
/* ecat_loop.c - EtherCAT raw-socket soak test: N x BRD(0x0000,len 2), then APRD of ESC identity.
 * Build: gcc -O2 -o ecat_loop ecat_loop.c ; Run: sudo ./ecat_loop eth0 [count] [period_us] */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <net/if.h>
#include <arpa/inet.h>
#include <linux/if_packet.h>

static int s; static uint8_t mac[6];
static int xfer(uint8_t cmd, uint16_t adp, uint16_t ado, int dlen, uint8_t idx, uint8_t *out, uint16_t *wkc)
{
	uint8_t f[64], r[1600]; int flen = 14 + 2 + 10 + dlen + 2, n, tries = 0;
	memset(f, 0, sizeof f); memset(f, 0xff, 6); memcpy(f + 6, mac, 6); f[12] = 0x88; f[13] = 0xA4;
	uint16_t el = ((10 + dlen + 2) & 0x7ff) | (1 << 12); f[14] = el; f[15] = el >> 8;
	f[16] = cmd; f[17] = idx; f[18] = adp; f[19] = adp >> 8; f[20] = ado; f[21] = ado >> 8; f[22] = dlen;
	if (flen < 60) flen = 60;
	if (send(s, f, flen, 0) < 0) return -1;
	while (tries++ < 4) {
		n = recv(s, r, sizeof r, 0);
		if (n < 28 + dlen) return -2;
		if (r[12] == 0x88 && r[13] == 0xA4 && r[17] == idx) {
			memcpy(out, r + 26, dlen); *wkc = r[26 + dlen] | (r[27 + dlen] << 8); return n;
		}
	}
	return -3;
}
int main(int argc, char **argv)
{
	const char *ifn = argc > 1 ? argv[1] : "eth0";
	int count = argc > 2 ? atoi(argv[2]) : 1000, period = argc > 3 ? atoi(argv[3]) : 1000;
	struct ifreq ifr; struct sockaddr_ll sll = {0}; struct timeval tv = {0, 200000};
	int i, ok = 0, lost = 0, bad = 0; uint8_t d[16]; uint16_t wkc; struct timespec a, b; long maxus = 0; double tot = 0;
	s = socket(AF_PACKET, SOCK_RAW, htons(0x88A4));
	if (s < 0) { perror("socket"); return 1; }
	strncpy(ifr.ifr_name, ifn, IFNAMSIZ - 1); ioctl(s, SIOCGIFINDEX, &ifr);
	sll.sll_family = AF_PACKET; sll.sll_ifindex = ifr.ifr_ifindex; sll.sll_protocol = htons(0x88A4);
	bind(s, (struct sockaddr *)&sll, sizeof sll);
	ioctl(s, SIOCGIFHWADDR, &ifr); memcpy(mac, ifr.ifr_hwaddr.sa_data, 6);
	setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
	for (i = 0; i < count; i++) {
		clock_gettime(CLOCK_MONOTONIC, &a);
		int n = xfer(0x07, 0, 0x0000, 2, i & 0xff, d, &wkc);
		clock_gettime(CLOCK_MONOTONIC, &b);
		long us = (b.tv_sec - a.tv_sec) * 1000000L + (b.tv_nsec - a.tv_nsec) / 1000;
		if (n < 0) lost++; else if (wkc != 1) bad++; else { ok++; tot += us; if (us > maxus) maxus = us; }
		if (period) usleep(period);
	}
	printf("BRD x%d: ok=%d lost=%d badwkc=%d  rt avg=%.0fus max=%ldus\n", count, ok, lost, bad, ok ? tot / ok : 0, maxus);
	/* APRD slave 0: type/rev/build (0x0000), DL status (0x0110), AL status (0x0130) */
	if (xfer(0x01, 0, 0x0000, 10, 0xA1, d, &wkc) > 0)
		printf("APRD 0x0000 wkc=%u: type=0x%02x rev=0x%02x build=0x%04x fmmu=%u sm=%u ram=%uKB ports=0x%02x feat=0x%04x\n",
		       wkc, d[0], d[1], d[2] | d[3] << 8, d[4], d[5], d[6], d[7], d[8] | d[9] << 8);
	if (xfer(0x01, 0, 0x0110, 2, 0xA2, d, &wkc) > 0) printf("APRD DL status wkc=%u: 0x%04x\n", wkc, d[0] | d[1] << 8);
	if (xfer(0x01, 0, 0x0130, 2, 0xA3, d, &wkc) > 0) printf("APRD AL status wkc=%u: 0x%04x\n", wkc, d[0] | d[1] << 8);
	return 0;
}
