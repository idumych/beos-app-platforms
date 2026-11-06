/* ftouch: reads "tap X Y", "down X Y", "move X Y", "up", "mouse X Y" lines
   on stdin and plays them through KWin's fake input (touch id 0). */
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <wayland-client.h>
#include "fake-input.h"
static struct org_kde_kwin_fake_input *fi;
static void global(void *d, struct wl_registry *r, uint32_t name, const char *iface, uint32_t v) {
	if (strcmp(iface, org_kde_kwin_fake_input_interface.name) == 0)
		fi = wl_registry_bind(r, name, &org_kde_kwin_fake_input_interface, v < 4 ? v : 4);
}
static void global_remove(void *d, struct wl_registry *r, uint32_t n) {}
static const struct wl_registry_listener rl = { global, global_remove };
int main(void) {
	struct wl_display *dpy = wl_display_connect(NULL);
	if (!dpy) { fprintf(stderr, "no display\n"); return 1; }
	struct wl_registry *reg = wl_display_get_registry(dpy);
	wl_registry_add_listener(reg, &rl, NULL);
	wl_display_roundtrip(dpy);
	if (!fi) { fprintf(stderr, "no fake input (not authorized?)\n"); return 1; }
	org_kde_kwin_fake_input_authenticate(fi, "ftouch", "touch tests");
	wl_display_roundtrip(dpy);
	setvbuf(stdout, NULL, _IOLBF, 0);
	printf("ready\n");
	char line[128];
	while (fgets(line, sizeof line, stdin)) {
		int x, y;
		if (sscanf(line, "down %d %d", &x, &y) == 2) {
			org_kde_kwin_fake_input_touch_down(fi, 0, wl_fixed_from_int(x), wl_fixed_from_int(y));
			org_kde_kwin_fake_input_touch_frame(fi);
		} else if (sscanf(line, "move %d %d", &x, &y) == 2) {
			org_kde_kwin_fake_input_touch_motion(fi, 0, wl_fixed_from_int(x), wl_fixed_from_int(y));
			org_kde_kwin_fake_input_touch_frame(fi);
		} else if (strncmp(line, "up", 2) == 0) {
			org_kde_kwin_fake_input_touch_up(fi, 0);
			org_kde_kwin_fake_input_touch_frame(fi);
		} else if (strncmp(line, "press", 5) == 0) {
			org_kde_kwin_fake_input_button(fi, 272, 1);
		} else if (strncmp(line, "release", 7) == 0) {
			org_kde_kwin_fake_input_button(fi, 272, 0);
		} else if (sscanf(line, "mouse %d %d", &x, &y) == 2) {
			org_kde_kwin_fake_input_pointer_motion_absolute(fi, wl_fixed_from_int(x), wl_fixed_from_int(y));
		} else
			continue;
		wl_display_roundtrip(dpy);
		printf("ok %s", line);
	}
	return 0;
}
