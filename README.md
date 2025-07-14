# [YouMAD?](https://www.youmad.org)

![Version](https://img.shields.io/badge/version-1.0.1-blue) ![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20WSL-green) ![License](https://img.shields.io/badge/license-BSD--3--Clause-orange)

**Your Music Album Downloader**

Downloads albums from YouTube Music. Yeah, we know. Another downloader script. How original. But this one actually works without making you want to throw your laptop out the window.

<img src="https://github.com/youmad-app/youmad-shell/blob/main/youmad-logo.png" width="500">

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
sudo apt install ffmpeg exiftool jq
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
Create a file called `urls.txt` in the same folder as the script:

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

This one is optional, end with just the `;` for an empty `RELEASETYPE` tag.

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
```

## What You Get

✅ **High-quality audio** - Not potato quality like some tools  
✅ **Proper metadata** - Album art, track numbers, cleaned up and Plex-ready  
✅ **Organized files** - Sorted like a normal human being would  
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

**Q: Is this legal?**  
A: Ask your lawyer, not us.

**Q: Why is it called YouMAD?**  
A: Because you're insane if you're using any other tool. Keep up.

**Q: Can it download video?**  
A: No. It's a MUSIC downloader. Reading is fundamental.

**Q: Why doesn't it work?**  
A: Did you install the dependencies? Did you read the instructions? Try that first.

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
