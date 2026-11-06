/* vptr [WIDTH HEIGHT]: reads "move X Y" / "down BTN" / "up BTN" / "scroll N" lines on stdin
   and plays them through a wlroots virtual pointer. BTN: 272 left, 273 right, 274 middle. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <wayland-client.h>
#include "virtual-pointer.h"
static struct zwlr_virtual_pointer_manager_v1 *mgr;
static void global(void *d, struct wl_registry *r, uint32_t name, const char *iface, uint32_t v) {
	if (strcmp(iface, zwlr_virtual_pointer_manager_v1_interface.name) == 0)
		mgr = wl_registry_bind(r, name, &zwlr_virtual_pointer_manager_v1_interface, 1);
}
static void global_remove(void *d, struct wl_registry *r, uint32_t n) {}
static const struct wl_registry_listener rl = { global, global_remove };
static uint32_t now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1000 + t.tv_nsec / 1000000; }
int main(int argc, char **argv) {
	unsigned W = argc > 2 ? atoi(argv[1]) : 1280, H = argc > 2 ? atoi(argv[2]) : 800;
	struct wl_display *dpy = wl_display_connect(NULL);
	if (!dpy) { fprintf(stderr, "no display\n"); return 1; }
	struct wl_registry *reg = wl_display_get_registry(dpy);
	wl_registry_add_listener(reg, &rl, NULL);
	wl_display_roundtrip(dpy);
	if (!mgr) { fprintf(stderr, "no virtual pointer manager\n"); return 1; }
	struct zwlr_virtual_pointer_v1 *p = zwlr_virtual_pointer_manager_v1_create_virtual_pointer(mgr, NULL);
	wl_display_roundtrip(dpy);
	char line[128];
	setvbuf(stdout, NULL, _IOLBF, 0);
	printf("ready\n");
	while (fgets(line, sizeof line, stdin)) {
		int a, b;
		if (sscanf(line, "move %d %d", &a, &b) == 2)
			zwlr_virtual_pointer_v1_motion_absolute(p, now(), a, b, W, H);
		else if (sscanf(line, "down %d", &a) == 1)
			zwlr_virtual_pointer_v1_button(p, now(), a, 1);
		else if (sscanf(line, "up %d", &a) == 1)
			zwlr_virtual_pointer_v1_button(p, now(), a, 0);
		else if (sscanf(line, "scroll %d", &a) == 1)
			zwlr_virtual_pointer_v1_axis_discrete(p, now(), 0, wl_fixed_from_int(a * 15), a);
		else
			continue;
		zwlr_virtual_pointer_v1_frame(p);
		wl_display_roundtrip(dpy);
		printf("ok %s", line);
	}
	return 0;
}
