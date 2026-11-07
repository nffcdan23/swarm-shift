# REVIEW: SWARM//SHIFT social ad, "One Run"

Vertical (1080 x 1920, 30 fps), 25.6 s, for TikTok, Instagram Reels and YouTube Shorts. Final file: `renders/swarm-shift-ad-9x16.mp4`.

## Creative calls

- Built storyline A, **One Run** (STORYLINES.md): the run clock is the spine, 0:00 to the boss at 5:00. Not built: B, "Which would you pick?" (the three level-up cards each playing their weapon, split screen to one), and C, "One thumb" (a real thumb on a real phone, one continuous take; needs filmed hands).
- Every word on screen comes from the game: the tagline "ONE CORE. ENDLESS SWARM." (data/game.json), "Drag to move. Everything else is automatic." (GAME_DESIGN.md), weapon names, "absurd by minute four" (GAME_DESIGN.md). The game's own UI does the rest: SECTOR 01, DRAG ANYWHERE TO MOVE, RUN LEVEL 2, WARNING THE OVERSEER, PHASE 4, SECTOR CLEARED.
- Look: the game's palette and Open Sans (the engine's font), the lobby wordmark rebuilt in type exactly as `home_screen.gd` builds it, the shipped app icon, the lobby's PLAY button, real Swarmer sprites on the end card.
- Sound: the game's own combat track (124 BPM) entering at its bar 5 so PLAY FREE lands on the A minor downbeat; the game's own sound effects throughout; the music muffles to 900 Hz under the level-up screen exactly as the game does.

## How the footage was made, and what was staged

All footage is the real game (Godot 4.7.2) recorded frame-perfect with Movie Maker at 1080 x 1920, 60 fps, by `tests/ad_capture.gd` (`tests/` is excluded from app exports). It runs on an in-memory profile, so no real save was touched. Staging, so that whoever runs the ad can judge it against the platforms' rules on representing gameplay:

- **Hook:** a core that never levelled (the HUD reads RUN LV 1 at 4:17), standing still, with a ring of 460 enemies spawned around it. A real run makes swarms this size, but not this tidy a ring.
- **Montage:** each clip is a real run in a different sector with the featured weapon granted at level 5 (evolved), plus a pack of extra enemies spawned so the weapon has something to hit.
- **Payoff and boss:** builds granted rather than earned (four weapons, within the real slot limit); the player kept invulnerable so health bars stay full; in-run banners hidden in the montage, hook and payoff.
- **Level-up:** the hand Arc Caster / Seeker Missiles / Orbit Blades was chosen (it is a hand the game can deal); the tap is a real tap on the real screen.
- **Boss:** after 9 s of the real fight the Overseer's health was dropped to 1.5% so the kill fits the ad; phase 4, the death and SECTOR CLEARED are the game's own.
- The thumb's joystick in the opening is the game's real stick, driven by synthetic touches.

## Measured, looked at, not checked

- `hyperframes check`: no errors, no warnings. Snapshots, cut strips and the 360 px phone sheet reviewed; frames decoded from the render checked against them.
- Sound **measured, not heard**: -14.6 LUFS integrated, -2.6 dBFS peak, no clipping; every added effect placed so its measured peak lands one frame after its picture. Nobody has listened to the mix.
- Not checked: how each platform's own interface sits over it on a real phone (the layout keeps text within 168-1330 px and clear of the right-hand rail, from the HyperFrames vertical guide).

## Weakest shot, and what I would do with more time

- The first montage clip (Seeker Missiles): the missiles are small at that zoom. More takes per weapon, with the camera closer, would give a stronger peak moment.
- The music is the game's procedurally generated loop (mono, 32 kHz). For paid ads, a produced track with a real drop on the payoff would lift it.
- A 15 s cut-down (hook, pick, ABSURD., boss, end card) for placements that favour short ads.

## Before this runs

- **Do not run it before launch.** The call to action ("PLAY FREE / ON THE APP STORE") is written for the live listing, and "free" assumes the planned free-to-play release. Both are variables on the end card host in `index.html` (and in Studio).
- No App Store badge is used. At launch, download Apple's official badge from Apple's marketing tools if you want it on the end card.

## Warnings kept on purpose

None.
