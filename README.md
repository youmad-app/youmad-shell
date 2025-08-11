# [YouMAD?](https://www.youmad.org)

![Version](https://img.shields.io/badge/version-1.1.0-blue) ![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20WSL-green) ![License](https://img.shields.io/badge/license-BSD--3--Clause-orange)

**Your Music Album Downloader**

Downloads albums from YouTube Music. Yeah, we know. Another downloader script. How original. But this one actually works without making you want to throw your laptop out the window.

<img src="https://github.com/youmad-app/youmad-shell/blob/main/youmad-neon-dark.png" width="500">

## Why YouMAD? Exists

Because you're tired of:
- Spotify removing your favorite albums without warning
- YouTube Music's terrible offline functionality  
- Being told what you can and can't do with music
- Complicated scripts that break every other week
- Plex having a complete meltdown because your metadata isn't perfect

## What It Does

Downloads entire albums from YouTube Music with one command. That's it. No PhD in computer science required.

```bash
./youmad.sh
```

Congratulations, you just learned the entire interface.

## Installation (For Humans)

**Stop panicking.** It's easier than setting up your printer.

**Dependencies** (install these first, genius):
```bash
# Ubuntu/Debian (because of course you use Ubuntu)
sudo apt install ffmpeg exiftool jq opustags
pip install yt-dlp --user

# macOS (fancy, aren't we?)
brew install ffmpeg exiftool jq yt-dlp
```

**Get YouMAD?:**
```bash
curl -LO https://github.com/youmad-app/youmad-shell/raw/main/youmad.sh
chmod +x youmad.sh
```

Done. See? We told you it was easy.

## How To Use (Rocket Science Not Required)

### Step 1: Add Your URLs
Create a file called `urls.txt` in the same folder as you run the script from:

```
https://music.youtube.com/playlist?list=OLAK5uy_example;Artist Name
https://music.youtube.com/playlist?list=OLAK5uy_example;Artist Name;
https://music.youtube.com/playlist?list=OLAK5uy_example;Artist Name;ep
https://music.youtube.com/playlist?list=OLAK5uy_example;Artist Name;live
```

Format: `URL;Artist Name;Release Type`

**Artist Name** (Because YouTube Music doesn't understand that an album is made by _someone_):
- This sets album artist to what you want, no more split albums in Plex
- This will also be the folder name where the albums are downloaded
- Use any character, including whitespace, except semicolon (because that's the separator, doh!)

**Release Types** (because Plex is picky):
- `album` - Regular albums (default, obviously)
- `ep` - EPs (not albums, apparently)  
- `single` - Singles (one song, much wow)
- `live` - Live albums (for when studio wasn't good enough)
- `comp` - Compilations (greatest hits, etc.)

This one is optional, Leave it out for the default (album). End with just the `;` for an empty `RELEASETYPE` tag.

**Only the URL** (because life's short):   
- If you enter just the URL, and nothing more, the Album Artist will be set to `Unknown Artist`. Are you really that lazy?

### Step 2: Run The Thing
```bash
./youmad.sh
```

**First time?**
It'll ask you some questions on audio format, rate-limiting, and browser cookies. Answer them. It's not a quiz.

```bash
./youmad.sh
=== YouMAD? Configuration ===
Leave blank to use defaults shown in brackets.

Preferred audio format (m4a, mp3, opus, flac, wav) [m4a]: m4a
Maximum download rate (e.g., 4M, 1M, 500K) [4M]:
Browser to extract cookies from (chrome, chromium, brave, firefox, safari, edge) [chrome]: chromium
```

### Step 3: Wait
Go make coffee. Browse Reddit. Question your life choices. The script is working.

### Step 4: Enjoy Your Music
Files appear in neat folders like: `Artist_Name/Album_Title/01 - Song.m4a`

Because unlike some people, we believe in organization.

## Command Options (For Show-Offs)

```bash
./youmad.sh --help          # Read the manual (shocking concept)
./youmad.sh --dry-run       # Pretend to download (commitment issues?)
./youmad.sh --verbose       # See ALL the technical gibberish
./youmad.sh --config        # Change your mind about settings
./youmad.sh --override      # Download everything again (wasteful)
./youmad.sh --playlist      # Simple playlist mode (skip the fancy stuff)
./youmad.sh --preserve      # Keep original format, ignores format in the config-file (audiophile mode)
```

### ✓ [See it in Action](https://github.com/youmad-app/youmad-shell/tree/main#appendix-see-it-in-action) ← Click the link for examples

### Advanced Options

**Playlist Mode (`--playlist`)**
- Downloads playlists directly without individual track processing
- Great for downloading your own curated playlists
- Simple folder structure: `Artist/Playlist-name/Track.ext`
- Preserves original track names from YouTube
- No metadata processing or track renumbering
- Perfect for when you just want the music, not the perfectionism

**Preserve Format (`--preserve`)**
- Keeps original audio format from YouTube (usually WebM)
- No re-encoding = maximum quality preservation
- Still organizes files and adds metadata
- Great for audiophiles who want zero quality loss
- Files might be in various formats (WebM, M4A, etc.)

**Pro Tips:**
- Use `--playlist --preserve` together for maximum speed and quality
- Use `--preserve --override` to re-download in original format
- Combine with `--verbose` to see what's actually happening

## What You Get

✅ **High-quality audio** - Not potato quality like some tools  
✅ **Proper metadata** - Album art, track numbers, cleaned up and Plex-ready  
✅ **Organized files** - Sorted like a normal human being would  
✅ **Format flexibility** - Convert to your preferred format or keep originals  
✅ **No duplicates** - Because we're not savages  
✅ **Clean filenames** - No weird Unicode disasters  
✅ **Cross-platform** - Works on your Linux, Mac, or Windows-with-WSL setup  

## What Could Go Wrong

⚠️ **YouTube changes stuff** - Not our fault when Google breaks things  
⚠️ **You need cookies** - From your browser, not the edible kind  
⚠️ **Downloads take time** - We're being polite, unlike you  
⚠️ **Large files** - Music takes space, revolutionary concept  
⚠️ **Copyright laws exist** - Don't be stupid about this  

## FAQ (Frequently Avoided Questions)

**Q: Why is it called YouMAD?**  
A: Because that's the one question that pops up when adding media to Plex.  
And, it's short for "*Your Music Album Downloader*". Catchy, ey?

**Q: Can it download video?**  
A: No. It's a MUSIC downloader. Reading is fundamental.

**Q: What's the difference between normal mode and playlist mode?**  
A: Normal mode processes each track individually with proper metadata. Playlist mode just downloads the whole thing as-is. Faster, but less fancy.

**Q: Should I use preserve mode?**  
A: If you want maximum quality and don't care about file formats, yes. If you want everything in MP3 or M4A, no.

**Q: Why doesn't it work?**  
A: Did you install the dependencies? Did you read the instructions? Try that first.

**Q: I did that, why do I still get all sorts of errors?**  
A: Google changes stuff. Make sure you update yt-dlp to the latest version.

**Q: Can you add feature X?**  
A: Create an issue. We'll consider it if it's not terrible.

**Q: This is too complicated!**  
A: It's literally one command. Maybe stick to Spotify.

## Requirements

- A functioning brain (negotiable)
- Linux, macOS, or WSL (Windows users: install WSL first)
- The dependencies listed above
- Basic reading comprehension
- Patience (downloads take time, Karen)

## License

BSD-3-Clause. Use it, abuse it, don't blame us when things go sideways.

---

**Made with ❤️ and excessive amounts of caffeine**  

---

*P.S. - Star this repo if it saved you from subscription hell. We're needy like that.*

---

# Appendix: See it in Action

## Normal Operation
This is the default mode. 

YouMAD? will download whatever is in your `urls.txt`, convert the files to the format of your choice, clean up metadata and folders/names:

**Run the command:**

```
$ ./youmad.sh
[2025-07-16 15:38:27] [INFO] Starting YouMAD?
[2025-07-16 15:38:27] [INFO] YouMAD? configuration loaded: m4a, 4M, chromium
[2025-07-16 15:38:27] [INFO] YouMAD? dependencies found: yt-dlp, ffmpeg, exiftool, jq
[2025-07-16 15:38:27] [INFO] YouMAD? processing URLs from ./urls.txt
[2025-07-16 15:38:27] [INFO] YouMAD? found 1 valid URLs

[1/1] Aunt Mary - Album - Janus
Extracting tracks from playlist... found 9 tracks
  ✓ Track 1/9 downloaded
  ✓ Track 2/9 downloaded
  ...
  ✓ Track 7/9 downloaded
  ✓ Track 8/9 downloaded
  ✓ Track 9/9 downloaded
  ✅ Album download completed successfully in 3 minutes and 29 seconds
  📝 Metadata updated
[2025-07-16 15:42:11] [INFO] YouMAD? all downloads completed successfully. Processed 1 URLs.
[2025-07-16 15:42:11] [INFO] YouMAD? all downloads processed successfully. ./urls.txt has been cleared.
[2025-07-16 15:42:11] [INFO] YouMAD? session complete. Check /home/hask01/youmad/activity.log for full details.
```

**File output:**

```
$ tree Aunt_Mary/
Aunt_Mary/
└── Janus
    ├── 01 - Path Of Your Dream.m4a
    ├── 02 - Mr. Kaye.m4a
    ...
    ├── 07 - All We've Got To Do Is Dream.m4a
    ├── 08 - Candles Of Heaven.m4a
    └── 09 - What A Lovely Day.m4a
```

**Metadata:**

```
$ mediainfo "Aunt_Mary/Janus/01 - Path Of Your Dream.m4a"
General
Complete name                            : Aunt_Mary/Janus/01 - Path Of Your Dream.m4a
Format                                   : MPEG-4
Format profile                           : Apple audio with iTunes info
Codec ID                                 : M4A  (M4A /isom/iso2)
File size                                : 13.4 MiB
Duration                                 : 4 min 7 s
Overall bit rate mode                    : Constant
Overall bit rate                         : 453 kb/s
Album                                    : Janus
Album/Performer                          : Aunt Mary
Track name                               : Path Of Your Dream
Track name/Position                      : 1
Performer                                : Aunt Mary
Recorded date                            : 20180720
Writing application                      : Lavf60.16.100
Cover                                    : Yes
trk                                      : 1

Audio
ID                                       : 1
Format                                   : AAC LC
Format/Info                              : Advanced Audio Codec Low Complexity
Codec ID                                 : mp4a-40-2
Duration                                 : 4 min 7 s
Source duration                          : 4 min 7 s
Source_Duration_LastFrame                : -1 ms
Bit rate mode                            : Constant
Bit rate                                 : 419 kb/s
Channel(s)                               : 2 channels
Channel layout                           : L R
Sampling rate                            : 48.0 kHz
Frame rate                               : 46.875 FPS (1024 SPF)
Compression mode                         : Lossy
Stream size                              : 12.4 MiB (93%)
Source stream size                       : 12.4 MiB (93%)
Language                                 : English
Default                                  : Yes
Alternate group                          : 1
```

## Preserve Mode

If you want the original files, **without re-encoding**, and don't care about a consistent format, use `--preserve`  
This will still give you formatted files/folders. Original metadata is left intact, "Album Artist" and "RELEASETYPE" may be added, depending on the format.

**Run the command:**

```
$ ./youmad.sh --preserve
[2025-07-16 15:20:51] [INFO] Starting YouMAD?
[2025-07-16 15:20:51] [INFO] YouMAD? preserve format mode enabled - no re-encoding.
[2025-07-16 15:20:51] [INFO] YouMAD? configuration loaded: m4a, 4M, chromium
[2025-07-16 15:20:51] [INFO] YouMAD? dependencies found: yt-dlp, ffmpeg, exiftool, jq
[2025-07-16 15:20:51] [INFO] YouMAD? processing URLs from ./urls.txt
[2025-07-16 15:20:51] [INFO] YouMAD? found 1 valid URLs

[1/1] Aunt Mary - Album - Janus
Extracting tracks from playlist... found 9 tracks
  ✓ Track 1/9 downloaded
  ✓ Track 2/9 downloaded
  ✓ Track 3/9 downloaded
  ...
  ✓ Track 9/9 downloaded
  ✅ Album download completed successfully in 2 minutes and 11 seconds
  📝 Metadata updated
[2025-07-16 15:23:07] [INFO] YouMAD? all downloads completed successfully. Processed 1 URLs.
[2025-07-16 15:23:07] [INFO] YouMAD? all downloads processed successfully. ./urls.txt has been cleared.
[2025-07-16 15:23:07] [INFO] YouMAD? session complete. Check /home/hask01/youmad/activity.log for full details.
```

**File output:**

```
$ tree Aunt_Mary
Aunt_Mary/
└── Janus
    ├── 01 - Path Of Your Dream.webm
    ├── 02 - Mr. Kaye.webm
    ├── 03 - Nocturnal Voice.webm
    ...
    └── 09 - What A Lovely Day.webm
```

**Metadata:**

```
$ mediainfo "Aunt_Mary/Janus/01 - Path Of Your Dream.webm"
General
Complete name                            : Aunt_Mary/Janus/01 - Path Of Your Dream.webm
Format                                   : WebM
Format version                           : Version 4
File size                                : 4.00 MiB
Duration                                 : 4 min 7 s
Overall bit rate                         : 136 kb/s
Track name                               : Path Of Your Dream
Description                              : Provided to YouTube by Universal Music Group /  / Path Of Your Dream · Aunt Mary /  / Janus /  / ℗ 1990 PolyGram A/S, Norway /  / Released on: 1973-01-01 /  / Composer Lyricist: Svein Gundersen / Composer Lyricist: Bjørn Christiansen /  / Auto-generated by YouTube.
Writing application                      : Lavf60.16.100
Writing library                          : Lavf60.16.100
Comment                                  : https://www.youtube.com/watch?v=c9maLcNDtYQ
ALBUM                                    : Janus
ARTIST                                   : Aunt Mary
DATE                                     : 20180720
PURL                                     : https://www.youtube.com/watch?v=c9maLcNDtYQ
SYNOPSIS                                 : Provided to YouTube by Universal Music Group /  / Path Of Your Dream · Aunt Mary /  / Janus /  / ℗ 1990 PolyGram A/S, Norway /  / Released on: 1973-01-01 /  / Composer Lyricist: Svein Gundersen / Composer Lyricist: Bjørn Christiansen /  / Auto-generated by YouTube.

Audio
ID                                       : 1
Format                                   : Opus
Codec ID                                 : A_OPUS
Duration                                 : 4 min 7 s
Channel(s)                               : 2 channels
Channel layout                           : L R
Sampling rate                            : 48.0 kHz
Bit depth                                : 32 bits
Compression mode                         : Lossy
Language                                 : English
Default                                  : Yes
Forced                                   : No
```

## Persistent + Playlist

Introducing the `--playlist` option will also bypass metadata cleanup.  
Combined with `--preserve`, your files will not be reencoded, metadata stays untouched, but there is still some effort to keep the files organized.

**Run the command:**

```
$ ./youmad.sh --preserve --playlist
[2025-07-16 15:26:43] [INFO] Starting YouMAD? v1.1.0
[2025-07-16 15:26:43] [INFO] YouMAD? preserve format mode enabled - no re-encoding.
[2025-07-16 15:26:43] [INFO] YouMAD? playlist mode enabled.
[2025-07-16 15:26:43] [INFO] YouMAD? configuration loaded: m4a, 4M, chromium
[2025-07-16 15:26:43] [INFO] YouMAD? dependencies found (playlist mode): yt-dlp, ffmpeg, jq
[2025-07-16 15:26:43] [INFO] YouMAD? processing URLs from ./urls.txt (playlist mode)
[2025-07-16 15:26:43] [INFO] YouMAD? found 1 valid URLs

[1/1] Aunt Mary - Album - Janus (playlist mode)
Downloading playlist... done
  ✅ Playlist download completed successfully in 1 minutes and 38 seconds

[2025-07-16 15:28:28] [INFO] YouMAD? all playlist downloads completed successfully. Processed 1 URLs.
[2025-07-16 15:28:28] [INFO] YouMAD? all playlist downloads processed successfully. ./urls.txt has been cleared.
[2025-07-16 15:28:28] [INFO] YouMAD? session complete. Check /home/hask01/youmad/activity.log for full details.
```

**File output:**

```
$ tree Aunt_Mary/
Aunt_Mary/
└── Album - Janus
    ├── All We've Got To Do Is Dream.webm
    ...
    ├── Path Of Your Dream.webm
    ├── Stumblin' Stone.webm
    └── What A Lovely Day.webm
```

**Metadata:**

```
$ mediainfo "Aunt_Mary/Album - Janus/Path Of Your Dream.webm"
General
Complete name                            : Aunt_Mary/Album - Janus/Path Of Your Dream.webm
Format                                   : WebM
Format version                           : Version 4
File size                                : 4.00 MiB
Duration                                 : 4 min 7 s
Overall bit rate                         : 136 kb/s
Track name                               : Path Of Your Dream
Description                              : Provided to YouTube by Universal Music Group /  / Path Of Your Dream · Aunt Mary /  / Janus /  / ℗ 1990 PolyGram A/S, Norway /  / Released on: 1973-01-01 /  / Composer Lyricist: Svein Gundersen / Composer Lyricist: Bjørn Christiansen /  / Auto-generated by YouTube.
Writing application                      : Lavf60.16.100
Writing library                          : Lavf60.16.100
Comment                                  : https://www.youtube.com/watch?v=c9maLcNDtYQ
ALBUM                                    : Janus
ARTIST                                   : Aunt Mary
DATE                                     : 20180720
PURL                                     : https://www.youtube.com/watch?v=c9maLcNDtYQ
SYNOPSIS                                 : Provided to YouTube by Universal Music Group /  / Path Of Your Dream · Aunt Mary /  / Janus /  / ℗ 1990 PolyGram A/S, Norway /  / Released on: 1973-01-01 /  / Composer Lyricist: Svein Gundersen / Composer Lyricist: Bjørn Christiansen /  / Auto-generated by YouTube.

Audio
ID                                       : 1
Format                                   : Opus
Codec ID                                 : A_OPUS
Duration                                 : 4 min 7 s
Channel(s)                               : 2 channels
Channel layout                           : L R
Sampling rate                            : 48.0 kHz
Bit depth                                : 32 bits
Compression mode                         : Lossy
Language                                 : English
Default                                  : Yes
Forced                                   : No
```
