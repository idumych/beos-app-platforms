// tone.cpp: plays a sine through the system mixer (BSoundPlayer), for audio tests.
//   tone FREQ LEFT_AMP RIGHT_AMP SECONDS
// Build in a Haiku-family guest: g++ tone.cpp -o tone -lbe -lmedia
// Capture the output with qemu-vm.sh (AUDIO=wav) and check it with sine-check.py.
#include <Application.h>
#include <SoundPlayer.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static double sFreq, sLeft, sRight, sPhase;

static void
Fill(void*, void* buffer, size_t size, const media_raw_audio_format& format)
{
	float* out = (float*)buffer;
	size_t frames = size / (sizeof(float) * 2);
	for (size_t i = 0; i < frames; i++) {
		float s = sin(sPhase);
		sPhase += 2 * M_PI * sFreq / format.frame_rate;
		out[2 * i] = sLeft * s;
		out[2 * i + 1] = sRight * s;
	}
}

int
main(int argc, char** argv)
{
	if (argc < 5)
		return 2;
	sFreq = atof(argv[1]); sLeft = atof(argv[2]); sRight = atof(argv[3]);
	BApplication app("application/x-vnd.jdsp-tone");
	media_raw_audio_format format = media_raw_audio_format::wildcard;
	format.format = media_raw_audio_format::B_AUDIO_FLOAT;
	format.channel_count = 2;
	format.frame_rate = 48000;
	format.byte_order = B_MEDIA_LITTLE_ENDIAN;
	BSoundPlayer player(&format, "tone", Fill);
	if (player.InitCheck() != B_OK) {
		fprintf(stderr, "player: %s\n", strerror(player.InitCheck()));
		return 1;
	}
	player.SetHasData(true);
	player.Start();
	usleep((useconds_t)(atof(argv[4]) * 1000000));
	player.Stop();
	return 0;
}
