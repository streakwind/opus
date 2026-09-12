# Install Opus (Linux)

Extract the archive into a prefix such as `~/.local`:

```sh
mkdir -p ~/.local
tar -xzf Opus-linux-x86_64.tar.gz -C ~/.local
~/.local/bin/opus
```

The archive bundles the Swift runtime, GTK 4, SQLite, and related libraries. A normal Linux desktop with a working display server (Wayland or X11) is required. No separate Swift installation is needed.

Optional desktop integration:

```sh
update-desktop-database ~/.local/share/applications
gtk-update-icon-cache ~/.local/share/icons/hicolor || true
```

Data is stored at `~/.local/share/opus/Opus.sqlite` (or `$XDG_DATA_HOME/opus/Opus.sqlite`). Set `OPUS_DATA_DIR` to use an isolated database.
