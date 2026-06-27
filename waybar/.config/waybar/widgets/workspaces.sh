#!/usr/bin/env python3

import html
import json
import os
import socket
import subprocess
import sys
import time


ACTIVE_COLOR = os.environ.get("WAYBAR_WORKSPACE_ACTIVE_COLOR", "#dbbc7f")
RELEVANT_EVENTS = {
    "workspace",
    "workspacev2",
    "focusedmon",
    "focusedmonv2",
    "createworkspace",
    "createworkspacev2",
    "destroyworkspace",
    "destroyworkspacev2",
    "moveworkspace",
    "moveworkspacev2",
    "renameworkspace",
}


def hyprctl_json(command):
    output = subprocess.check_output(["hyprctl", "-j", command], text=True)
    return json.loads(output)


def print_workspaces():
    active_id = hyprctl_json("activeworkspace").get("id")
    workspaces = sorted(hyprctl_json("workspaces"), key=lambda item: item.get("id", 0))
    active_color = html.escape(ACTIVE_COLOR, quote=True)
    labels = []

    for workspace in workspaces:
        name = html.escape(str(workspace.get("name", "")))
        if workspace.get("id") == active_id:
            labels.append(f'<span foreground="{active_color}"><b>[{name}]</b></span>')
        else:
            labels.append(name)

    print(json.dumps({"text": " ".join(labels), "class": ["waybar-workspaces"]}), flush=True)


def event_socket_path():
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR")
    signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")

    if not runtime_dir or not signature:
        return None

    return os.path.join(runtime_dir, "hypr", signature, ".socket2.sock")


def watch_events():
    print_workspaces()

    while True:
        path = event_socket_path()
        if not path:
            time.sleep(1)
            print_workspaces()
            continue

        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
                client.connect(path)
                with client.makefile("r", encoding="utf-8", errors="replace") as events:
                    for line in events:
                        event = line.partition(">>")[0]
                        if event in RELEVANT_EVENTS:
                            print_workspaces()
        except OSError:
            time.sleep(1)


if len(sys.argv) > 1 and sys.argv[1] == "--watch":
    watch_events()
else:
    print_workspaces()
