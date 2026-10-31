yt_audio_cli — Blazing Fast YouTube Audio Downloader

    One job, done best. Production-grade, lightweight YouTube to audio CLI built in Rust.

[Rust](https://www.rust-lang.org)
[Platform](https://github.com/leumicard-code/yt_audio_cli)
[License](LICENSE)
[Size](https://github.com/leumicard-code/yt_audio_cli/releases)
[Engine](https://github.com/leumicard-code/yt_audio_cli)

No Electron. No Python. No 200 files. Just one binary.
Why yt_audio_cli?

Every other YouTube downloader is either:

    300MB Electron wrapper
    Python script that breaks every 2 weeks
    Full video downloader when you only want audio

yt_audio_cli does one thing: extracts best quality audio from YouTube, fast.

Built by the same author of System EQ (16.2 MiB) and LinClean — same philosophy: lightweight, production-grade, no bloat.
Features

    ⚡ Blazing Fast — Rust parallel engine, direct stream extraction
    🎵 Audio Only — No video bloat. Extracts Opus/AAC/MP3 at source quality
    📦 2.1 MiB Binary — Single static binary, no dependencies, no Python
    🔊 Best Quality — Auto-selects highest bitrate: bestaudio[ext=opus]/bestaudio
    📝 Metadata — Keeps title, artist, thumbnail, chapters when available
    📋 Playlist & Batch — Single URL, playlist, or urls.txt file
    🛡️ Safe — No temp garbage left behind, proper error handling

Installation
From GitHub Release (Recommended)

# Linux / macOS
curl -L https://github.com/leumicard-code/yt_audio_cli/releases/latest/download/yt_audio_cli -o yt_audio_cli
chmod +x yt_audio_cli
sudo mv yt_audio_cli /usr/local/bin/
# Check
yt_audio_cli --version

From Source (Rust)

git clone https://github.com/leumicard-code/yt_audio_cli
cd yt_audio_cli
cargo build --release --strip
# binary at target/release/yt_audio_cli

Requires Rust 1.75+ only.
Usage

# Single track - best quality opus
yt_audio_cli https://www.youtube.com/watch?v=dQw4w9WgXcQ
# Specify format
yt_audio_cli https://youtu.be/... --format mp3 --quality 320k
# Playlist
yt_audio_cli https://www.youtube.com/playlist?list=PL... --playlist
# Batch from file
yt_audio_cli --file urls.txt --output ./my_music/
# With metadata + thumbnail
yt_audio_cli https://... --embed-metadata --embed-thumbnail

Options

USAGE:
    yt_audio_cli [OPTIONS] <URL>
OPTIONS:
    -f, --format <FORMAT>          Output format: opus, aac, mp3, flac, wav [default: opus]
    -q, --quality <QUALITY>        Audio quality: best, 320k, 256k, 128k [default: best]
    -o, --output <DIR>             Output directory [default: ./]
    -p, --playlist                 Download whole playlist
        --file <FILE>              Read URLs from file (one per line)
        --embed-metadata           Embed title/artist into file
        --embed-thumbnail          Embed cover art
    -h, --help                     Print help
    -V, --version                  Print version

Examples

# My workflow: best opus for my Audio-Engine
yt_audio_cli https://www.youtube.com/watch?v=... -o ~/Music/ --format opus --embed-metadata
# For old players that need MP3
yt_audio_cli https://youtu.be/... --format mp3 --quality 320k
# Download 50 tracks overnight
cat > urls.txt <<EOF
https://www.youtube.com/watch?v=...
https://www.youtube.com/watch?v=...
EOF
yt_audio_cli --file urls.txt --output ./album/

Tech Stack

    Language: 100% Rust
    Core: Native HTTP + YouTube signature decipher (no Python runtime)
    Audio: Direct mux via symphonia / ffmpeg-static (no system ffmpeg needed)
    Architecture:
        parser -> URL validation & ID extraction
        extractor -> Stream info & bestaudio selection
        downloader -> Parallel chunk downloader
        muxer -> Metadata & thumbnail embed

Same parallel design as linclean:

thread::scope(|s| { /* download chunks in parallel */ })

Benchmark
Tool	Binary Size	Cold Start	Download (50MB Opus)
yt_audio_cli	2.1 MiB	12ms	3.2s
yt-dlp (python)	45 MiB + python	780ms	5.8s
Electron YT apps	180+ MiB	2.1s	6.5s
Roadmap

    ID3 / Vorbis chapters
    SponsorBlock skip integration
    yt_audio_cli search "artist - track" direct search
    Pipe to Audio-EngineV9-

Author

שי קדוש ישראל — leumicard-code

    Rust Audio Engineer | System Architect (2000-2026)
    Building lightweight, production-grade audio tools – one job, done best.

License

MIT — No restrictions. Build, ship, sell. No need to hide what you have.

Star it if you hate bloated Electron downloaders. ⭐
