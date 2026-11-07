# SPEC: SWARM//SHIFT, "One Run" (vertical social ad)

GOAL: a stranger scrolling TikTok stops on a lone core about to be swallowed by hundreds of enemies, understands within 20 s that one thumb drags and the build becomes absurd, and taps through to play.

OUTPUT: HyperFrames, 1080 x 1920, 30 fps, H.264 MP4.

TIME: 25.645 s x 30 = 770 frames = 53 beats of the game's combat track. 124 BPM: 0.48387 s and 14.516 frames per beat, 58.065 frames per bar. Beat k lands at round(k x 14.516). The track enters at its bar 5 (file 7.742 s, F major) and loops to its bar 1 (A minor) at beat 48, under the call to action.

## LOOK

The medium is the game itself: neon vector line-art on a navy grid. Everything the ad adds is set in the game's own type and colours (src/ui/palette.gd, src/ui/ui_theme.gd, the lobby wordmark).

- Ground: real gameplay, full bleed, never scaled below 1.0 or placed in a frame. The end card is #05070D (Palette.BG) with the arena grid (#16324A lines every 96 px at 70%) and one soft radial of #2DE2FF at 18% behind the icon, as the game's splash screen has.
- Ink: #EAF6FF (Palette.TEXT). Muted: #7C8DA6.
- Player accent: #2DE2FF cyan (the core, "ONE CORE.", the clock's progress bar, the PLAY button).
- Brand accent: #FF3D9A magenta, rationed to the "//": the wordmark and the shift wipes. "ENDLESS SWARM." takes the swarm's own pink #FF6B9A.
- Event colours from the game: gold #FFD15C for "ABSURD." (the colour of a crit), red #FF4D5E for the boss beat (the warning banner's colour).
- Display face: Open Sans (the game's font, Godot's bundled Open Sans), caps only. Headlines 800, tracking 0.02em. Labels 700, tracking 0.14em, like the in-game banners (spacing 7 at size 62). Wordmark 600, tracking 0.11em, with the lobby's halo: a same-colour shadow of 16 px at 16%.
- Sizes at 1080 wide: hook lines 132 px; clock 168 px; beat headline 96 px; weapon label 64 px; end-card wordmark 104 px; tagline 40 px; CTA 64 px. Nothing read under 34 px.
- Legibility over footage: a dark halo on every word (text-shadow 0 0 18 px and 0 0 44 px of #05070D at 90% and 70%), plus a radial scrim of #05070D at 70% centred on the top band (50% 20%) in shots with a busy top. No plates, no cards.
- Layout band (TikTok and Reels UI): nothing read above 168 px or below 1330 px; nothing read right of 930 px between 850 and 1650 px. The clock sits at 210 to 380 px, beat headlines at 400 to 640 px, the core at 960 px.

## OBJECTS

- The core: the player's cyan hexagon in its ring, with green Orbit Blades. The hero of the hook and the end card's icon (assets/brand/icon.png, the shipped app icon: the same core inside eight enemies).
- The swarm: pink arrowheads (swarmers), orange hexagons (Brutes), green four-squares (Splitters), as rendered by the game.
- The clock: the game's run timer, made large: M:SS digits on rolling strips, ticking with the footage's own HUD time, with a cyan progress bar under it that fills to 5:00, the boss (the game's own run-progress bar along the top of the HUD).
- The "//": two magenta parallelograms slanted 20 degrees, 120 px wide with a 56 px gap, the wordmark's slashes made physical. They are the wipe.
- The level-up screen, cards and the thumb's joystick: real UI from the take, never redrawn.
- The PLAY button: the lobby's primary button, cyan fill #2DE2FF, text #05070D, radius 26 px.

## MOTION

- Eases: arrivals expo.out (titles 0.18 s, blur 10 px to 0, no slide); camera and floods power2.inOut; exits and zoom-throughs power3.in; the clock's digit rolls power3.out 0.32 s, one second's tick 0.12 s.
- Springs: the icon lands on back.out(1.25) (about 0.75 damping), the PLAY button on back.out(1.6). Opacity and colour never bounce.
- Titles land and hold dead still. Exits are 40-50% of their entrance and go with the cut.
- Staggers: words 0.07 s, wordmark letters 0.035 s.
- Footage speed: 1.0 everywhere except the boss kill (0.5). The picked card is held (rate 0.1) for the zoom-through.
- Motion blur: render-time (data-motion-blur on the root), so the wipes, the zoom-through and the clock's rolls smear along their path instead of showing in-between digits.
- Real camera moves come from the game's camera (zoomed in the capture), not from scaling footage. The only scale on footage is the zoom-through the picked card.

## SHOTS

| Frames | Beats | Shot | Hero move | Reads (window) | Sound | Hand-off |
| --- | --- | --- | --- | --- | --- | --- |
| 0-72 | 0-5 | HOOK. hook.mp4 from 0.10 s: the lone core at zoom 1.7, then the game camera pulls back to 0.74 on a ring of 460 enemies | the game camera's pull-back (0.55-1.95 s) | "ONE CORE." from frame 0 (thumbnail); "ENDLESS SWARM." lands beat 3 | music at full from frame 0; the take's own sound | the clock spins 4:17 back to 0:00 as the "//" wipes left to right |
| 73-159 | 5-11 | 0:00. start.mp4 from 0.25 s: SECTOR 01, "DRAG ANYWHERE TO MOVE", the thumb's joystick, the first kills | the core moving under the thumb | clock 0:00-0:02; "DRAG TO MOVE." beat 6; "EVERYTHING ELSE IS AUTOMATIC." beat 8 | the game's reroll spin on the rewind; the take | hard cut on beat 11 to the level-up (same run) |
| 160-217 | 11-15 | PICK 1 OF 3. start.mp4 from 5.30 s: RUN LEVEL 2, three cards, the tap on SEEKER MISSILES at 6.54 s | the tap and the card lighting | the game's own "RUN LEVEL 2 / CHOOSE AN UPGRADE"; clock hidden | music muffled to 700 Hz like the game, opens on the tap | zoom through the picked card: 1.0 to 3.6 in 0.36 s, power3.in |
| 218-391 | 15-27 | MONTAGE. Seeker Missiles (Ember Field 2:09), Prism Lance (Violet Rift 2:32), Singularity (Toxic Bloom 3:10), Plasma Mines (Cyan Grid 3:36), 3 beats each | each weapon at its peak | clock rolls 0:05, 2:09, 2:32, 3:10, 3:36; the weapon's name, 64 px label | the takes; hard cuts on the beat | the "//" wipes into minute four |
| 392-507 | 27-35 | PAYOFF. payoff.mp4 4:29: Prism Wheel, Hive Pods, Singularity, chain explosions | the camera punch (1.045, 0.45 s) as ABSURD. lands | clock 4:29-4:33; "ABSURD." slams on beat 28 in gold | the take; the game's large explosion on the slam | red flood over everything, clock included (compositions/flood.html), into the warning |
| 508-623 | 35-43 | BOSS. Sector 20, Crimson Void: WARNING THE OVERSEER, 5:00 the wall closes, the fight, the kill at 0.5 | the Overseer's death blast | clock 4:55 to 5:00, bar full; the game's own warning banner | the take's warning and death sounds | the kill's white-out becomes the end card |
| 624-770 | 43-53 | END CARD. The core left alone after the kill becomes the shipped app icon; 22 real Swarmer sprites ring the lockup and orbit at 3 degrees a second; SWARM//SHIFT letters in; the tagline; PLAY FREE on beat 48 | the icon's spring and the wordmark | wordmark from beat 44, "ONE CORE. ENDLESS SWARM." beat 46, PLAY FREE / ON THE APP STORE beat 48 to the end (2.4 s) | the game's victory jingle on beat 44, its reward sound on PLAY FREE, the track's A minor downbeat on the CTA; 0.9 s fade out | hold |

## BANNED

A dark void with small things floating in it (the end card is the game's grid and its real icon, filled); glow, bloom and particles added on top of footage (the only glow is the brand's own: the wordmark halo and the splash radial); purple or blue gradients, glass cards, plates behind text; the cream-paper serif-mono look; everything fading and sliding up; text moving while read; breathing or pulsing loops; corner brackets, frame borders, HUD readouts as decoration (the clock is the run's real time, tied to the footage); three cards in a row as a graphic (the level-up cards are the game's own screen); the logo docked in a corner; a phone mock-up frame around the game; the App Store badge drawn from memory; a drawn hand.

## QA

- Frame 0: "ONE CORE." legible over the lone core: the thumbnail.
- 1.6 s: "ENDLESS SWARM." with the ring visible behind it.
- 2.5 s: mid-wipe; the "//" bars on the seam.
- 3.6 s: the joystick visible; "DRAG TO MOVE." legible.
- 6.6 s: the tapped card lit; music muffled in the mix.
- 7.1 s: inside the zoom-through.
- 8.0, 9.4, 10.9, 12.3 s: one per weapon, name and clock legible.
- 14.0 s: "ABSURD." over the payoff.
- 17.2, 18.6, 20.0 s: warning, 5:00 arrival, kill.
- 21.4, 22.6, 24.5 s: icon, wordmark, CTA.
- At 360 px wide (the phone sheet): every line above still reads.

## MIX (measured on the draft render, not heard)

- Music: the game's combat track at 1.35 (track alone -18.8 LUFS). Muffled to 900 Hz from 5.30 to 6.54 s, as the game muffles it under the level-up screen.
- Takes: the game's own sound effects, set so continuous gameplay sits about 5 dB under the music (montage 0.32-0.42, payoff 0.30, boss 0.45-0.60) and the opening's UI sounds (level-up, the pick) sit on top (1.1-1.2).
- Hits (the game's own files, each peaking one frame after its picture): reroll on the rewind, surge on both wipes and the zoom-through, explosion_l on ABSURD., boss_die on the kill, victory on beat 44, reward on PLAY FREE.
- Whole film: -14.6 LUFS integrated, -2.6 dBFS peak, no clipping.
