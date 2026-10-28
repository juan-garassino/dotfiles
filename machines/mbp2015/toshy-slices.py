###  SLICE_MARK_START: kbtype_override  ###  EDITS OUTSIDE THESE MARKS WILL BE LOST ON UPGRADE

keyboards_UserCustom_dct = {
    # Add your keyboard device here if its type is misidentified.
    # Valid types to map device to: Apple, Windows, IBM, Chromebook (case sensitive)
    # Example:
    'My Keyboard Device Name': 'Apple',
    'Apple Inc. Apple Internal Keyboard / Trackpad': 'Apple',
}

###  SLICE_MARK_END: kbtype_override  ###  EDITS OUTSIDE THESE MARKS WILL BE LOST ON UPGRADE

###  SLICE_MARK_START: user_custom_functions  ###  EDITS OUTSIDE THESE MARKS WILL BE LOST ON UPGRADE

def paste_image_or_text():
    """⌘V in terminals: Ctrl+V when the clipboard holds an image (Claude Code reads images
    itself on a real Ctrl+V), the terminal's Ctrl+Shift+V text paste otherwise."""
    def _paste(ctx):
        try:
            types = subprocess.run(['wl-paste', '--list-types'], capture_output=True,
                                   text=True, timeout=0.5).stdout
        except (OSError, subprocess.TimeoutExpired):
            types = ''
        return C("C-v") if 'image/' in types else C("C-Shift-v")
    return _paste

###  SLICE_MARK_END: user_custom_functions  ###  EDITS OUTSIDE THESE MARKS WILL BE LOST ON UPGRADE

###  SLICE_MARK_START: user_apps  ###  EDITS OUTSIDE THESE MARKS WILL BE LOST ON UPGRADE


keymap("User hardware keys", {
    # PUT UNIVERSAL REMAPS FOR HARDWARE KEYS HERE
    # KEYMAP WILL BE ACTIVE IN ALL DESKTOP ENVIRONMENTS/DISTROS


}, when = lambda ctx:
    cnfg.screen_has_focus and
    not ctx_app_is_remote
)

keymap("User overrides terminals", {
    C("RC-V"):                  paste_image_or_text(),          # screenshots paste into Claude Code too
}, when = lambda ctx:
    cnfg.screen_has_focus and
    ctx_app_is_terminal
)

###  SLICE_MARK_END: user_apps  ###  EDITS OUTSIDE THESE MARKS WILL BE LOST ON UPGRADE
