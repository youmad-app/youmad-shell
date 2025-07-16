no beta currently available.

TODO for next version:
 - Convert WebM → Opus, without reencoding (ffmpeg -i input.webm -c:a copy output.opus)
   - Consider if this should be the default mode, as it's bitperfect downloads.
   - Add metadata (including custom fields), using ffmpeg
   - Embed cover art
 - Remove WebM as supported format, and clean up some cluttered logic
 - Keep exiftool for all other formats, avoid retesting stuff that works
   - ffmpeg is already a requirement for yt-dlp
