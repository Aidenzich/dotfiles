#!/usr/bin/env python3
"""Apply scrollback settings to already-running iTerm2 sessions."""

import sys

import iterm2


if len(sys.argv) != 2:
    raise SystemExit("usage: iterm2-live-profile.py <profile-name>")

target_profile = sys.argv[1]


async def main(connection):
    app = await iterm2.async_get_app(connection)
    updated = 0

    for window in app.terminal_windows:
        for tab in window.tabs:
            for session in tab.sessions:
                profile = await session.async_get_profile()
                if profile.name not in {target_profile, "tmux"}:
                    continue

                await profile.async_set_mouse_reporting_allow_mouse_wheel(False)
                await profile.async_set_scrollback_in_alternate_screen(True)
                await profile.async_set_scrollback_with_status_bar(True)
                print(
                    "[iterm2] live session updated: "
                    f"{session.session_id} ({profile.name})"
                )
                updated += 1

    print(f"[iterm2] live sessions updated: {updated}")


iterm2.run_until_complete(main)
