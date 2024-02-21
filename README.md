# Fork of hUGEDriver for the Mega Duck (version without compression)
This is a fork of [hUGEDriver](https://github.com/SuperDisk/hUGEDriver) which supports running on the Mega Duck (a console clone of the Game Boy with some register address and bit order changes).

- If you want the MegaDuck version with compression, see here: https://github.com/bbbbbr/hUGEDriver/tree/uncap

The source edits for MegaDuck are not opitmized, they're just `ifdef`ed in for ease of seeing what has to be handled differently. The changes should not add much overhead though.

### Binaries
Check Releases for compiled, ready-to-use object files

### Building (GBDK)

- Have RGBDS and GBDK-2020 installed and in the system path

- Mega Duck
  - `cd gbdk_example`
  - `mkdir obj; mkdir build; mkdir lib`
  - `rgbasm -DGBDK -DTARGET_MEGADUCK -o./obj/hUGEDriver_megaduck.obj -i.. ../hUGEDriver.asm`
  - `python ../tools/rgb2sdas.py -o obj/hUGEDriver_megaduck.o obj/hUGEDriver_megaduck.obj`
  - `sdar -ru lib/hUGEDriver_megaduck.lib obj/hUGEDriver_megaduck.o`
  - Produces: `lib/hUGEDriver_megaduck.lib`
  - Build example: `lcc -msm83:duck -I../include -Wl-llib/hUGEDriver_megaduck.lib -o build/gbdk_player_example.duck src/gbdk_player_example.c src/sample_song.c`

- Game Boy (if needed)
  - `cd gbdk_example`
  - `mkdir obj; mkdir build; mkdir lib`
  - `rgbasm -DGBDK -o./obj/hUGEDriver.obj -i.. ../hUGEDriver.asm`
  - `python ../tools/rgb2sdas.py -o obj/hUGEDriver.o obj/hUGEDriver.obj`
  - `sdar -ru lib/hUGEDriver.lib obj/hUGEDriver.o`
  - Produces: `lib/hUGEDriver.lib`
  - Build example: `lcc -I../include -Wl-llib/hUGEDriver.lib -o build/gbdk_player_example.gb src/gbdk_player_example.c src/sample_song.c`

### To make either resulting object file compatible with older GBDK versions before GBDK-2020 4.1.0
- Edit the resulting `.lib` file and replace `-msm83` with `-mgbz80`

---------------------------

# Original Repo Readme Contents Below
(Many thanks to SuperDisk for making hUGEDriver and hUGETracker!)

---------------------------

![hUGEDriver](https://github.com/SuperDisk/hUGEDriver/assets/1688837/a6079751-20b5-4db3-bb48-0e748234f8ca)
===

This is the repository for hUGEDriver, the music driver for the Game Boy which plays music created in [hUGETracker](https://github.com/SuperDisk/hUGETracker).

If you want help using the tracker, driver, or just want to chat, join the [hUGETracker Discord server!](https://discord.gg/abbHjEj5WH)

## Quick start (RGBDS)

1. Export your song in "RGBDS .asm" format in hUGETracker.
2. Choose a *song descriptor* name. This is what you will refer to the song as in your code. It must be a valid RGBDS symbol.
3. Place the exported `.asm` file in your RGBDS project.
4. Load `hl` with your song descriptor name, and `call hUGE_init`
5. In your game's main loop or in a VBlank interrupt, `call hUGE_dosound`
6. When assembling your game, be sure to specify your music file and hUGEDriver.asm in your call to `rgbasm`/`rgblink`!

Be sure to enable sound playback before you start!

```asm
ld a, $80
ld [rAUDENA], a
ld a, $FF
ld [rAUDTERM], a
ld a, $77
ld [rAUDVOL], a
```

See the `rgbds_example` directory for a working example!

## Quick start (GBDK)

1. Export your song in "GBDK .c" format in hUGETracker.
2. Choose a *song descriptor* name. This is what you will refer to the song as in your code. It must be a valid C variable name.
3. Place the exported .C file in your GBDK project.
4. `#include "hUGEDriver.h"` in your game's main file
5. Define `extern const hUGESong_t your_song_descriptor_here` in your game's main file
6. Call `hUGE_init(&your_song_descriptor_here)` in your game's main file
7. In your game's main loop or in a VBlank interrupt, call `hUGE_dosound`
8. When compiling your game, be sure to specify your music file and `hUGEDriver.o` in your call to `lcc`!

Be sure to enable sound playback before you start!

```c
NR52_REG = 0x80;
NR51_REG = 0xFF;
NR50_REG = 0x77;
```

See `gbdk_example/src/gbdk_player_example.c` for a working example!

## Usage

This driver is suitable for use in homebrew games. hUGETracker exports data representing the various components of a song, as well as a *song descriptor* which is a small block of pointers that tell the driver how to initialize and play a song.

hUGETracker can export the data and song descriptor as a `.asm` or `.c` for use in RGBDS or GBDK based projects, respectively. Playing a song is as simple as calling hUGE_init with a pointer to your song descriptor, and then calling `hUGE_dosound` at a regular interval (usually on VBlank, the timer interrupt, or simply in your game's main loop)

In assembly:
```asm
ld hl, SONG_DESCRIPTOR
call hUGE_init

;; Repeatedly
call hUGE_dosound
```

In C:
```c
extern const hUGESong_t song;

// In your initializtion code
__critical {
    hUGE_init(&song);
    add_VBL(hUGE_dosound);
}
```

Check out `player.asm` for a full fledged example of how to use the driver in an RGBDS project, and `gbdk_example/gbdk_player_example.c` for usage with GBDK C likewise.

### `hUGE_mute_channel`

**Caution**:
As an optimization, hUGEDriver avoids loading the same wave present in wave RAM; when "muting" CH3 and loading your own wave, make sure to set `hUGE_current_wave` to `hUGE_NO_WAVE` (a dummy value) to force a refresh.

## License

hUGETracker and hUGEDriver are dedicated to the public domain.
