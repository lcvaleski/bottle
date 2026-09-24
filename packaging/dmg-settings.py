# dmgbuild settings for the Cable installer window.
# Writes .DS_Store directly (no Finder AppleScript), so it works on a CI runner.
import os

# dmgbuild exec()s this file, so __file__ isn't available; the caller passes the path.
app = os.environ["DMG_APP_PATH"]
app_name = os.path.basename(app)
here = os.environ.get("DMG_PACKAGING_DIR", os.path.join(os.getcwd(), "packaging"))

format = "UDZO"
size = None

files = [app]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(here, "volume.icns")

background = os.path.join(here, "dmg-background.png")
window_rect = ((360, 200), (600, 424))
icon_size = 128
text_size = 13
default_view = "icon-view"
show_icon_preview = False

# Chrome off: this window is a one-purpose instruction sheet.
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

arrange_by = None
grid_offset = (0, 0)
grid_spacing = 100
label_pos = "bottom"

icon_locations = {
    app_name: (155, 185),
    "Applications": (445, 185),
}
