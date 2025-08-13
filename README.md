# [YouMAD?](https://www.youmad.org) - https://YouMAD.org

![Version](https://img.shields.io/badge/version-2.1.2-blue) ![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20WSL-green) ![License](https://img.shields.io/badge/license-BSD--3--Clause-orange)

**Your Music Album Downloader**

Downloads albums and playlists from YouTube Music with a single command.  

Yeah, we know. Another downloader script. How original. But this one actually works without making you want to throw your laptop out the window. Besides, **this one downloads the highest audio quality and never does any re-encoding**.

**NOTE:** Due to a bug, YouMAD? will only download the first album in urls.txt. Please download albums individually, a fix is in the works.

<img src="https://github.com/youmad-app/youmad-shell/blob/main/youmad-neon.png" width="500">

## Why YouMAD? Exists

Because you're tired of:
- Spotify removing your favorite albums without warning
- YouTube Music's terrible offline functionality  
- Being told what you can and can't do with music
- Complicated scripts that break every other week
- Plex having a complete meltdown because your metadata isn't perfect

## What It Does

Downloads entire albums and playlists from YouTube Music with one command. No PhD in computer science required.

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
Create a file called `urls.txt` in the same folder:

```
https://music.youtube.com/playlist?list=OLAK5uy_example;Artist Name
https://music.youtube.com/playlist?list=OLAK5uy_example;Artist Name;ep
https://music.youtube.com/playlist?list=PLrAl6cWylHjwKpVROBfZyY5jzBCMjFhgs;Various;playlist
```

Format: `URL;Artist Name;Type`

**Artist Name** (Because YouTube Music doesn't understand that an album is made by _someone_):
- This sets album artist and folder name where albums are downloaded
- Use any character except semicolon (because that's the separator, doh!)

**Types**:
- `album` - Regular albums (default, obviously)
- `ep` - EPs (not albums, apparently)  
- `single` - Singles (one song, much wow)
- `live` - Live albums (for when studio wasn't good enough)
- `comp` - Compilations (greatest hits, etc.)
- `soundtrack` - Movie soundtracks
- `demo` - Demo recordings
- `remix` - Remix albums
- `playlist` - Downloads playlist as-is (simple mode, no fancy metadata)

Leave type blank for default (album).

### Step 2: Run The Thing
```bash
./youmad.sh
```

**First time?** You'll be guided through downloading dependencies. It'll also ask you some questions. Answer them. It's not a quiz.

```bash
./youmad.sh
=== YouMAD? Configuration ===
Leave blank to use defaults shown in brackets.

Maximum download rate (e.g., 4M, 1M, 500K) [4M]:
Browser for cookies (chrome, chromium, brave, firefox, safari, edge) [chrome]:
```

### Step 3: Wait
Go make coffee. Browse Reddit. Question your life choices. The script is working.

### Step 4: Enjoy Your Music
Files appear in neat folders like: `Artist_Name/Album_Title/01 - Song.opus`

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

✅ **Highest quality audio** - Opus or M4A, no re-encoding, no quality loss  
✅ **Perfect metadata** - Album art, track numbers, cleaned up and Plex-ready  
✅ **Organized files** - Sorted like a normal human being would  
✅ **No duplicates** - Because we're not savages  
✅ **Clean filenames** - No weird Unicode disasters  
✅ **Mixed downloads** - Albums and playlists in one session  
✅ **Cross-platform** - Works on your Linux, Mac, or Windows-with-WSL setup  

## Album vs Playlist Mode

**Album Mode (default):**
- Downloads tracks individually with proper numbering and metadata
- Fetches thumnail, converts it from 16:9 format to square, saves it as `cover.jpg` in the album folder
- Converts WebM to Opus, keeps M4A as-is
- Perfect for albums that need to be organized
- File output: `01 - Track Name.opus`

**Playlist Mode (add `;playlist` to URL):**
- Downloads entire playlist directly
- Preserves original track names from YouTube
- Playlists can be downloaded over and over, only new additions are grabbed
- Simple folder structure, no track renumbering
- Great for your own curated playlists
- File output: `Track Name.opus`

Both modes preserve maximum audio quality with zero re-encoding.

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

**Q: What's the difference between album and playlist mode?**  
A: Album mode processes each track individually with proper metadata. Playlist mode just downloads the whole thing as-is. Faster, but less fancy.

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
