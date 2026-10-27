# sourced by linux/norns.sh and linux/package.sh (and shipped next to norns.sh): the name that a person sees.
# the project, the package, the command, /opt/verdandi, the JACK client and MIDI port names, the environment variables and the
# files keep "Verdandi"/"verdandi": only what is shown in a window, a menu, a dialog or a package description uses this.
VERDANDI_DISPLAY_NAME="Verdandi Linux"
VERDANDI_TAGLINE="the Linux version of Verdandi, norns on the desktop"
# the X11 window class of the norns window (WM_CLASS, what the panel matches with StartupWMClass in the menu entry). norns.sh gives it to SDL
# (SDL_VIDEO_X11_WMCLASS), so it does not depend on the name of the program file or on how it was started
VERDANDI_WM_CLASS="norns"
