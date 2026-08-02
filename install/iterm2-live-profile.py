#!/usr/bin/env python3
"""Apply scrollback settings to iTerm2's saved profiles and live sessions."""

import sys

import iterm2


if len(sys.argv) != 4:
    raise SystemExit(
        "usage: iterm2-live-profile.py <profile-name> <local|off> <tmux-command>"
    )

target_profile = sys.argv[1]
tmux_mode = sys.argv[2]
tmux_command = sys.argv[3]

if tmux_mode not in {"local", "off"}:
    raise SystemExit(f"unsupported tmux mode: {tmux_mode}")


async def apply_scrollback_settings(profile):
    await profile.async_set_mouse_reporting(True)
    await profile.async_set_mouse_reporting_allow_mouse_wheel(True)
    await profile.async_set_scrollback_in_alternate_screen(True)
    await profile.async_set_scrollback_with_status_bar(True)
    await profile.async_set_disable_smcup_rmcup(False)


async def apply_tmux_mode(profile):
    if tmux_mode == "local":
        await profile.async_set_command(tmux_command)
        await profile.async_set_use_custom_command(
            iterm2.Profile.USE_CUSTOM_COMMAND_ENABLED
        )
    else:
        await profile.async_set_command("")
        await profile.async_set_use_custom_command(
            iterm2.Profile.USE_CUSTOM_COMMAND_DISABLED
        )


async def main(connection):
    app = await iterm2.async_get_app(connection)
    target_names = {target_profile, "tmux"}
    saved_updated = 0
    live_updated = 0

    # iTerm2 keeps its own in-memory profile templates while running. New
    # sessions clone these templates rather than rereading the preference
    # plist, so updating existing sessions alone is not durable.
    for partial in await iterm2.PartialProfile.async_query(connection):
        if partial.name not in target_names:
            continue

        profile = await partial.async_get_full_profile()
        await apply_scrollback_settings(profile)
        if profile.name == target_profile:
            await apply_tmux_mode(profile)
        print(
            "[iterm2] saved profile template updated: "
            f"{profile.name} ({profile.guid})"
        )
        saved_updated += 1

    if saved_updated == 0:
        raise RuntimeError(
            "no matching iTerm2 saved profile templates: "
            + ", ".join(sorted(target_names))
        )

    for window in app.terminal_windows:
        for tab in window.tabs:
            for session in tab.sessions:
                profile = await session.async_get_profile()
                if profile.name not in target_names:
                    continue

                await apply_scrollback_settings(profile)
                if profile.name == target_profile:
                    await apply_tmux_mode(profile)
                print(
                    "[iterm2] live session updated: "
                    f"{session.session_id} ({profile.name})"
                )
                live_updated += 1

    print(f"[iterm2] saved profile templates updated: {saved_updated}")
    print(f"[iterm2] live sessions updated: {live_updated}")


iterm2.run_until_complete(main)
