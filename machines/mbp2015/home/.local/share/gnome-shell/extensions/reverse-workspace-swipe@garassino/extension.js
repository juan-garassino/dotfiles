import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

// GNOME's TouchpadSwipeGesture only reads natural-scroll to pick the swipe
// direction, so handing the workspace trackers an inverted view of that one
// key flips workspace swipes while leaving two-finger scrolling alone.
export default class ReverseWorkspaceSwipe extends Extension {
    enable() {
        const trackers = [
            Main.wm._workspaceAnimation._swipeTracker,
            Main.overview._overview.controls._workspacesDisplay._swipeTracker,
        ];
        this._patched = trackers.map(tracker => {
            const gesture = tracker._touchpadGesture;
            const settings = gesture._touchpadSettings;
            gesture._touchpadSettings = {
                get_boolean: key => key === 'natural-scroll'
                    ? !settings.get_boolean(key) : settings.get_boolean(key),
            };
            return [gesture, settings];
        });
    }

    disable() {
        for (const [gesture, settings] of this._patched)
            gesture._touchpadSettings = settings;
        this._patched = null;
    }
}
