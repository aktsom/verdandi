# M27: ext folders on Linux, in the real norns (run_all.sh, ext_scenario; NORNS_PICKER=none, VERDANDI_TEST_HOOKS=1): the functions are registered, a dropped folder becomes an ext folder (the same event the window system sends),
# a dropped file is refused (nothing is imported or copied), the old import links are listed and removed (the original file stays, a copy is never listed), a removal takes away only the link, the page opens,
# and with no folder chooser installed the page gets a plain sentence. the folders are made by the "#sh" lines first.
#sleep 5
#sh mkdir -p "$NORNS_HOME/ext-src/Drops Samples" "$NORNS_HOME/dust/audio/mac" "$NORNS_HOME/old-originals" && echo RIFF-kick > "$NORNS_HOME/ext-src/Drops Samples/kick.wav" && echo RIFF-file > "$NORNS_HOME/ext-src/dropped-file.wav" && echo RIFF-old > "$NORNS_HOME/old-originals/old.wav" && ln -s "$NORNS_HOME/old-originals/old.wav" "$NORNS_HOME/dust/audio/mac/old.wav" && echo RIFF-copy > "$NORNS_HOME/dust/audio/mac/copy.wav"
print("PROBE ext registered", _norns.ext_list ~= nil, _norns.ext_add ~= nil, _norns.ext_remove ~= nil, _norns.ext_pick ~= nil, _norns.ext_sync ~= nil, _norns.ext_legacy_list ~= nil, _norns.test_drop ~= nil)
print("PROBE ext system page", tostring(_menu.m ~= nil and _menu.m["EXTRA"] ~= nil))
home = os.getenv("NORNS_HOME")
-- the old import links: the link is listed (the copy is not)
lg = _norns.ext_legacy_list()
print("PROBE legacy list", #lg, lg[1] and lg[1].name, lg[1] and lg[1].state)
-- a dropped folder is added
_norns.test_drop(home .. "/ext-src/Drops Samples")
#sleep 2
l = _norns.ext_list()
print("PROBE drop folder", #l, l[1] and l[1].name, l[1] and l[1].state)
-- a dropped file is refused: nothing in dust/audio, no new ext folder
_norns.test_drop(home .. "/ext-src/dropped-file.wav")
#sleep 2
print("PROBE drop file", #_norns.ext_list())
#sh ls -A "$NORNS_HOME/dust/audio" > "$NORNS_HOME/audio-after-drop.txt"; ls -A "$NORNS_HOME/dust/code" >> "$NORNS_HOME/audio-after-drop.txt"
-- the file browser's own listing sees the folder (ls -pL follows the link: a folder name ends with "/")
names = util.scandir(_path.audio)
seen = false
for _, n in ipairs(names) do if n == "[ext] Drops Samples/" then seen = true end end
print("PROBE browser sees", seen)
-- the page, with the folder and the old import link
_norns.open_extra_folders()
#sleep 1
print("PROBE page", _menu.page)
-- removing one old import link: the link goes, the original stays; a copy is refused
print("PROBE legacy refuse copy", select(1, _norns.ext_legacy_remove("copy.wav")), select(2, _norns.ext_legacy_remove("copy.wav")))
print("PROBE legacy remove", select(1, _norns.ext_legacy_remove("old.wav")))
#sh [ ! -e "$NORNS_HOME/dust/audio/mac/old.wav" ] && [ ! -L "$NORNS_HOME/dust/audio/mac/old.wav" ] && echo "legacy_link_gone=yes" >> "$MARKS"; [ -f "$NORNS_HOME/old-originals/old.wav" ] && echo "legacy_original_stays=yes" >> "$MARKS"; [ -f "$NORNS_HOME/dust/audio/mac/copy.wav" ] && echo "copy_stays=yes" >> "$MARKS"
-- removing the ext folder: the link only
print("PROBE ext remove", select(1, _norns.ext_remove("[ext] Drops Samples")))
#sh [ ! -e "$NORNS_HOME/dust/audio/[ext] Drops Samples" ] && echo "ext_link_gone=yes" >> "$MARKS"; [ -f "$NORNS_HOME/ext-src/Drops Samples/kick.wav" ] && echo "ext_files_stay=yes" >> "$MARKS"; [ ! -e "$NORNS_HOME/dust/audio/dropped-file.wav" ] && echo "file_not_imported=yes" >> "$MARKS"
-- no folder chooser (NORNS_PICKER=none): a plain sentence, nothing else
_norns.ext_folder_chosen = function(p, e) print("PROBE pick answer", p == "", e) end
_norns.ext_pick()
#sleep 2
print("PROBE ext folders done")
#xdo key ctrl+q
#sleep 4
