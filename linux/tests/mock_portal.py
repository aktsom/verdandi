#!/usr/bin/env python3
"""
a stand-in for xdg-desktop-portal's FileChooser, for linux/tests/run_all.sh: owns
org.freedesktop.portal.Desktop on the session bus, answers OpenFile like the real portal does (the
Request object at /org/freedesktop/portal/desktop/request/<sender>/<handle_token>, then a Response
signal with {"uris": [...]}) with the files named on the command line, and records the options it got
in <log>. it does not show a dialog, and it is not the portal of any desktop: what the real
portals do is for docs/port/HARDWARE-CHECKLIST.md.

usage: mock_portal.py <log> <file> [<file> ...]
"""
import json
import sys

import gi

gi.require_version("Gio", "2.0")
gi.require_version("GLib", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

LOG = sys.argv[1]
FILES = sys.argv[2:]

XML = """
<node>
  <interface name="org.freedesktop.portal.FileChooser">
    <method name="OpenFile">
      <arg type="s" name="parent_window" direction="in"/>
      <arg type="s" name="title" direction="in"/>
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="o" name="handle" direction="out"/>
    </method>
  </interface>
</node>
"""


def on_call(conn, sender, path, iface, method, params, invocation):
    parent, title, options = params.unpack()
    token = options.get("handle_token", "t")
    request = "/org/freedesktop/portal/desktop/request/%s/%s" % (sender[1:].replace(".", "_"), token)
    with open(LOG, "a") as f:
        f.write(json.dumps({"title": title, "parent": parent,
                            "multiple": options.get("multiple"), "directory": options.get("directory"),
                            "current_folder": bytes(options.get("current_folder", b"")).decode().rstrip("\0")}) + "\n")
    invocation.return_value(GLib.Variant("(o)", (request,)))

    def respond():
        uris = ["file://" + f for f in FILES]
        conn.emit_signal(sender, request, "org.freedesktop.portal.Request", "Response",
                         GLib.Variant("(ua{sv})", (0, {"uris": GLib.Variant("as", uris)})))
        return False

    GLib.timeout_add(300, respond)


def on_bus(conn, name):
    node = Gio.DBusNodeInfo.new_for_xml(XML)
    conn.register_object("/org/freedesktop/portal/desktop", node.interfaces[0], on_call, None, None)


Gio.bus_own_name(Gio.BusType.SESSION, "org.freedesktop.portal.Desktop", Gio.BusNameOwnerFlags.NONE, on_bus, None, None)
GLib.MainLoop().run()
