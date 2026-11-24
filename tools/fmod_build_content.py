#!/usr/bin/env python3
"""Build the game's FMOD events straight from the PVZGE library in the project.

The Studio project already carries every PVZGE clip under `Assets/PVZGE/`,
each with its `AudioFile` metadata. So adding an event is only a matter of
writing the event and pointing it at clips that are already there: nothing is
copied, extracted or probed, and the tool runs anywhere Python does.

Two inputs describe what to build:

  data/native/audio/fmod_content.json   sound effects: event path -> clips
  data/native/audio/music_map.json      every world's music cues

Effects become action sheets. Several clips go into one multi instrument with
its playlist shuffled, so FMOD picks the variation and the game never knows.
The content file's `music` section (event path -> clip) makes looping
timeline events for music outside the worlds, such as the menu.

A world's lawn music becomes one timeline event driven by the `state`
parameter - the same shape as the hand-built Egypt event:

  state 0      Choose Your Seeds
  state 1..3   phases one to three
  otherwise    the final phase

Each phase is its optional `_Start` intro followed by its `_LP` loop. An
unnamed loop region keeps the loop going; a named region with a condition on
`state` (the final one has none) is what moves playback on, exactly as Egypt
and Zomboss do it.

Existing events are left alone unless the content file marks them
`"replace": true`. Replacing keeps the event's GUID, folder and bank, so
nothing that refers to it breaks - but anything hand-tuned inside it is lost,
which is why an event with properties Studio only writes when you change
something (volume, pitch, ...) is refused rather than replaced.

Every event this tool touches is assigned to a bank (effects to Sound, music
to Music), so a build picks it up without a trip through Studio.

    python3 tools/fmod_build_content.py <project dir> [--dry-run]
    python3 tools/fmod_build_content.py <project dir> --streams <out.json>

`--streams` writes the Godot fallback's stream map instead: for every catalog
event, the clips its FMOD event plays, as `res://Music/Assets/...` paths.
"""
import glob, json, os, re, sys, uuid
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
CONTENT = os.path.join(ROOT, "data", "native", "audio", "fmod_content.json")
MUSIC_MAP = os.path.join(ROOT, "data", "native", "audio", "music_map.json")
CATALOG = os.path.join(ROOT, "data", "native", "audio", "events.json")
STREAM_ROOT = "res://Music/Assets/"
STATE_PARAMETER = "state"
# Top-level event folder -> the bus its events feed. The game's settings
# screen sets volume on these by name, so they are part of the contract.
BUSES = {"Music": "Music", "SFX": "SFX"}

# Properties Studio writes into an event only once someone has tuned it.
HAND_TUNED = {"volume", "pitch", "startOffset", "maxVoices", "voiceStealing",
              "cooldown", "priority", "isStream", "triggerChance",
              "randomizePitch", "randomizeVolume"}

# The cues a world can have besides its lawn music, as
# music_map key -> (event folder under Music/InGame, catalog prefix, loops).
WORLD_CUES = {
    "victory": ("Victory", "music.victory", False),
    "lose": ("Lose", "music.lose", False),
    "leave": ("Leave", "music.leave", False),
    "zomboss_intro": ("Zomboss/Intro", "music.zomboss.intro", False),
    "minigame": ("Minigame", "music.minigame", True),
    "ultimate_battle": ("UltimateBattle", "music.ultimate", True),
}

# PVZGE's tutorial track is "Tutorial"; the Studio event was named after the
# Front Lawn's player house before this tool existed, and the catalog follows.
EVENT_NAME = {"tutorial": "Playerhouse", "iceage": "Iceage", "lostcity": "Lostcity"}

# Eighties has no lawn phases of its own: PVZGE scores it with the Jam
# tracks. Punk is the one with an intro and a loop, so it carries the lawn.
WORLD_EXTRA = {
    "eighties": {"lawn_phase4": {"intro": "Punk_Start", "loop": "Punk_LP"}},
}


def guid():
    return "{%s}" % uuid.uuid4()


# --- reading the project -------------------------------------------------

class Project:
    def __init__(self, root):
        self.root = root
        meta = os.path.join(root, "Metadata")
        if not os.path.isdir(meta):
            raise SystemExit("not an FMOD Studio project: %s" % root)
        self.meta = meta
        master = open(os.path.join(meta, "Master.xml"), encoding="utf-8").read()
        self.model = re.search(r'serializationModel="([^"]+)"', master).group(1)
        self.master_bus = re.search(r'class="MixerMaster" id="(\{[^}]+\})"', master).group(1)

        self.groups = {}         # bus name -> MixerGroup id
        for f in glob.glob(os.path.join(meta, "Group", "*.xml")):
            for o in ET.parse(f).getroot().iter("object"):
                if o.get("class") == "MixerGroup":
                    self.groups[_prop(o, "name")] = o.get("id")

        self.folders = {}        # id -> (name, parent)
        self.master_folder = None
        for f in glob.glob(os.path.join(meta, "EventFolder", "*.xml")):
            o = ET.parse(f).getroot().find("object")
            if o.get("class") == "MasterEventFolder":
                self.master_folder = o.get("id")
            self.folders[o.get("id")] = (_prop(o, "name") or "", _rel(o, "folder"))

        self.banks = {}
        for f in glob.glob(os.path.join(meta, "Bank", "*.xml")):
            for o in ET.parse(f).getroot().iter("object"):
                if o.get("class") in ("Bank", "MasterBank"):
                    self.banks[_prop(o, "name")] = o.get("id")

        self.events = {}         # path -> file
        for f in glob.glob(os.path.join(meta, "Event", "*.xml")):
            o = ET.parse(f).getroot().find("object[@class='Event']")
            self.events[self._path(_rel(o, "folder"), _prop(o, "name"))] = f

        self.audio = {}          # asset path -> (id, seconds)
        for f in glob.glob(os.path.join(meta, "AudioFile", "*.xml")):
            o = ET.parse(f).getroot().find("object")
            self.audio[_prop(o, "assetPath")] = (o.get("id"), float(_prop(o, "length") or 0))
        self.by_name = {}        # clip name -> [asset path]
        for path in self.audio:
            self.by_name.setdefault(os.path.splitext(os.path.basename(path))[0], []).append(path)

        self.state_param = None
        for f in glob.glob(os.path.join(meta, "ParameterPreset", "*.xml")):
            r = ET.parse(f).getroot()
            preset = r.find("object[@class='ParameterPreset']")
            if preset is not None and _prop(preset, "name") == STATE_PARAMETER:
                self.state_param = _rel(preset, "parameter")

    def _path(self, fid, name):
        parts = [name]
        seen = set()
        while fid and fid != self.master_folder and fid in self.folders and fid not in seen:
            seen.add(fid)
            n, fid = self.folders[fid]
            parts.append(n)
        return "/".join(reversed(parts))

    def clip(self, ref):
        """A clip reference -> its asset path. A reference is a path under
        Assets/ (with or without the extension and the PVZGE/ prefix) or a
        bare clip name, which must be unambiguous."""
        for cand in (ref, ref + ".mp3", "PVZGE/" + ref, "PVZGE/SFX/" + ref,
                     "PVZGE/SFX/" + ref + ".mp3", "PVZGE/" + ref + ".mp3"):
            if cand in self.audio:
                return cand
        hits = self.by_name.get(ref, [])
        lib = [h for h in hits if h.startswith("PVZGE/")]
        if len(lib) == 1:
            return lib[0]
        if not hits:
            raise KeyError("no clip '%s' in the project" % ref)
        raise KeyError("clip '%s' is ambiguous: %s" % (ref, ", ".join(sorted(hits))))

    def folder_for(self, dirs, new_folders):
        parent = self.master_folder
        walked = []
        for d in dirs:
            walked.append(d)
            match = [fid for fid, (n, p) in self.folders.items() if n == d and p == parent]
            if match:
                parent = match[0]
                continue
            fid = guid()
            self.folders[fid] = (d, parent)
            new_folders.append((fid, d, parent))
            parent = fid
        return parent


def _prop(o, name):
    p = o.find("property[@name='%s']/value" % name)
    return p.text if p is not None else None


def _rel(o, name):
    d = o.find("relationship[@name='%s']/destination" % name)
    return d.text if d is not None else None


# --- writing XML ----------------------------------------------------------

class Doc:
    def __init__(self, model):
        self.root = ET.Element("objects", {"serializationModel": model})

    def obj(self, cls, oid=None, **props):
        o = ET.SubElement(self.root, "object", {"class": cls, "id": oid or guid()})
        for k, v in props.items():
            if v is None:
                continue
            p = ET.SubElement(o, "property", {"name": k})
            ET.SubElement(p, "value").text = _fmt(v)
        return o

    def write(self, path):
        ET.indent(self.root, space="\t")
        body = ET.tostring(self.root, encoding="unicode", short_empty_elements=True)
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write('<?xml version="1.0" encoding="UTF-8"?>\n' + body + "\n")


def _fmt(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float):
        v = round(v, 6)
        return str(int(v)) if v.is_integer() else repr(v)
    return str(v)


def rel(o, name, *dests):
    r = ET.SubElement(o, "relationship", {"name": name})
    for d in dests:
        ET.SubElement(r, "destination").text = d
    return r


def mixer_bits(doc, output):
    """The routing every event has: input -> master bus, and its own master."""
    mixer, emm, minput = guid(), guid(), guid()
    doc.obj("EventMixer", mixer).append(_r("masterBus", emm))
    mi = doc.obj("MixerInput", minput)
    chain_in, pan_in = _chain(doc), guid()
    rel(mi, "effectChain", chain_in)
    rel(mi, "panner", pan_in)
    rel(mi, "output", output)
    doc.obj("MixerBusPanner", pan_in)
    m = doc.obj("EventMixerMaster", emm)
    chain_m, pan_m = _chain(doc), guid()
    rel(m, "effectChain", chain_m)
    rel(m, "panner", pan_m)
    rel(m, "mixer", mixer)
    doc.obj("MixerBusPanner", pan_m)
    return mixer, emm, minput


def _r(name, dest):
    r = ET.Element("relationship", {"name": name})
    ET.SubElement(r, "destination").text = dest
    return r


def _chain(doc):
    chain, fader = guid(), guid()
    rel(doc.obj("MixerBusEffectChain", chain), "effects", fader)
    doc.obj("MixerBusFader", fader)
    return chain


def event_head(doc, eid, name, folder):
    e = doc.obj("Event", eid, name=name, outputFormat=1)
    rel(e, "folder", folder)
    return e


def bus_for(proj, path):
    """The mixer bus an event at `path` feeds: Music or SFX, by top folder."""
    return proj.groups.get(BUSES.get(path.split("/")[0]), proj.master_bus)


def action_sheet_event(proj, path, eid, name, folder, bank, clips):
    """A one-shot: action sheet -> multi instrument -> the clip(s)."""
    doc = Doc(proj.model)
    e = event_head(doc, eid, name, folder)
    mixer, emm, minput = mixer_bits(doc, bus_for(proj, path))
    track, props, marker, timeline, sheet, outer = (guid() for _ in range(6))
    for r, d in (("mixer", mixer), ("masterTrack", track), ("mixerInput", minput),
                 ("automatableProperties", props), ("markerTracks", marker),
                 ("timeline", timeline), ("parameters", sheet), ("banks", bank)):
        rel(e, r, d)
    t = doc.obj("MasterTrack", track)
    rel(t, "modules", outer)
    rel(t, "mixerGroup", emm)
    doc.obj("EventAutomatableProperties", props)
    doc.obj("MarkerTrack", marker)
    doc.obj("Timeline", timeline, isProxyEnabled=False)
    rel(doc.obj("ActionSheet", sheet), "modules", outer)

    sounds = []
    for c in clips:
        sid = guid()
        rel(doc.obj("SingleSound", sid), "audioFile", proj.audio[c][0])
        sounds.append(sid)
    if len(sounds) == 1:
        rel(doc.obj("MultiSound", outer), "sounds", sounds[0])
    else:
        inner = guid()
        rel(doc.obj("MultiSound", outer), "sounds", inner)
        rel(doc.obj("MultiSound", inner, playlistMode=1), "sounds", *sounds)
    _reorder(doc)
    return doc


def timeline_event(proj, path, eid, name, folder, bank, segments):
    """A timeline laid out from `segments`, each
    {clip, start, loop: bool, region: (pos, len, name, state|None) | None}."""
    doc = Doc(proj.model)
    e = event_head(doc, eid, name, folder)
    mixer, emm, minput = mixer_bits(doc, bus_for(proj, path))
    track, props, timeline, group, mgroup = (guid() for _ in range(5))
    loops_track, magnets_track = guid(), guid()
    for r, d in (("mixer", mixer), ("masterTrack", track), ("mixerInput", minput),
                 ("automatableProperties", props)):
        rel(e, r, d)
    rel(e, "markerTracks", loops_track, magnets_track)
    rel(e, "groupTracks", group)
    rel(e, "timeline", timeline)
    rel(e, "banks", bank)
    rel(doc.obj("MasterTrack", track), "mixerGroup", emm)
    doc.obj("EventAutomatableProperties", props)
    doc.obj("MarkerTrack", magnets_track)
    doc.obj("MarkerTrack", loops_track)

    sounds, markers, extra = [], [], []
    for seg in segments:
        sid = guid()
        seconds = proj.audio[seg["clip"]][1]
        s = doc.obj("SingleSound", sid, start=seg["start"] or None, length=seconds)
        rel(s, "audioFile", proj.audio[seg["clip"]][0])
        sounds.append(sid)
        if seg.get("loop"):
            lid = guid()
            markers.append(lid)
            extra.append(("LoopRegion", lid, dict(position=seg["start"], length=seconds),
                          loops_track, None))
        if seg.get("region"):
            pos, length, rname, state = seg["region"]
            rid = guid()
            markers.append(rid)
            extra.append(("LoopRegion", rid, dict(position=pos, length=length, name=rname,
                                                  looping=2), magnets_track, state))

    g = doc.obj("GroupTrack", group)
    rel(g, "modules", *sounds)
    rel(g, "mixerGroup", mgroup)
    tl = doc.obj("Timeline", timeline)
    rel(tl, "modules", *sounds)
    if markers:
        rel(tl, "markers", *markers)
    mg = doc.obj("EventMixerGroup", mgroup, name="Audio 1")
    chain, pan = _chain(doc), guid()
    rel(mg, "effectChain", chain)
    rel(mg, "panner", pan)
    rel(mg, "output", emm)
    doc.obj("MixerBusPanner", pan)

    for cls, oid, props_, mtrack, state in extra:
        o = doc.obj(cls, oid, **props_)
        rel(o, "timeline", timeline)
        rel(o, "markerTrack", mtrack)
        if state is not None:
            if proj.state_param is None:
                raise SystemExit("no '%s' parameter preset in the project" % STATE_PARAMETER)
            cid = guid()
            rel(o, "triggerConditions", cid)
            c = doc.obj("ParameterCondition", cid, minimum=state, maximum=state)
            rel(c, "parameter", proj.state_param)
    _reorder(doc)
    return doc


def _reorder(doc):
    """Event first, as Studio writes it; the rest in creation order."""
    objs = list(doc.root)
    ev = [o for o in objs if o.get("class") == "Event"]
    rest = [o for o in objs if o.get("class") != "Event"]
    for o in objs:
        doc.root.remove(o)
    for o in ev + rest:
        doc.root.append(o)


# --- what to build ----------------------------------------------------------

def lawn_segments(proj, world, cues):
    """Lay a world's lawn music out on one timeline, Egypt-style."""
    phases = [("choose_seeds", "Choose Your Seeds", 0), ("lawn_phase1", "First Wave", 1),
              ("lawn_phase2", "Mid Wave A", 2), ("lawn_phase3", "Mid Wave B", 3),
              ("lawn_phase4", "Final Wave", None)]
    present = [p for p in phases if p[0] in cues]
    segments, t = [], 0.0
    for i, (key, label, state) in enumerate(present):
        cue = cues[key]
        last = i == len(present) - 1
        begin = t
        if cue.get("intro"):
            intro = proj.clip(cue["intro"])
            segments.append({"clip": intro, "start": t})
            t += proj.audio[intro][1]
        loop = proj.clip(cue["loop"])
        seconds = proj.audio[loop][1]
        segments.append({"clip": loop, "start": t, "loop": True,
                         "region": (begin, t + seconds - begin, label,
                                    None if last else state)})
        t += seconds
    return segments


def plan(proj, content, music_map):
    """-> [(event path, kind, payload, replace)] for everything to build."""
    out = []
    for path, spec in sorted(content.get("sfx", {}).items()):
        if isinstance(spec, list):
            spec = {"clips": spec}
        out.append((path, "sfx", [proj.clip(c) for c in spec.get("clips", [])],
                    bool(spec.get("replace"))))
    for path in content.get("assign", []):
        out.append((path, "assign", None, False))
    for path, clip in sorted(content.get("music", {}).items()):
        out.append((path, "music_loop", [proj.clip(clip)], False))

    for world, cues in sorted(music_map["worlds"].items()):
        cues = dict(cues)
        cues.update(WORLD_EXTRA.get(world, {}))
        name = EVENT_NAME.get(world, world.capitalize())
        lawn = [k for k in cues if k.startswith("lawn_phase")]
        if world in ("tutorial",) or not lawn:
            pass        # Playerhouse is hand-built; Jam, Victory, Zomboss have no lawn
        else:
            out.append(("Music/InGame/%s" % name, "lawn", lawn_segments(proj, world, cues),
                        False))
        if world in ("victory", "zomboss", "jam"):
            continue
        for key, (folder, _prefix, loops) in WORLD_CUES.items():
            if key in cues:
                clip = proj.clip(cues[key]["oneshot"])
                out.append(("Music/InGame/%s/%s" % (folder, name),
                            "music_loop" if loops else "music_oneshot", [clip], False))
    return out


def catalog_ids(music_map):
    """The catalog entries the music events imply, id -> fmod path."""
    ids = {}
    for world, cues in music_map["worlds"].items():
        if world in ("victory", "zomboss", "jam"):
            continue
        name = EVENT_NAME.get(world, world.capitalize())
        cues = dict(cues)
        cues.update(WORLD_EXTRA.get(world, {}))
        if any(k.startswith("lawn_phase") for k in cues):
            ids["music.lawn.%s" % world] = "event:/Music/InGame/%s" % name
        for key, (folder, prefix, _loops) in WORLD_CUES.items():
            if key in cues:
                ids["%s.%s" % (prefix, world)] = "event:/Music/InGame/%s/%s" % (folder, name)
    return ids


# --- applying ---------------------------------------------------------------

def existing_state(path):
    root = ET.parse(path).getroot()
    ev = root.find("object[@class='Event']")
    tuned = sorted({p.get("name") for o in root for p in o.findall("property")} & HAND_TUNED)
    return ev.get("id"), _rel(ev, "folder"), _rel(ev, "banks"), tuned


def _clips_of(path):
    """The AudioFile ids an event's sounds play."""
    root = ET.parse(path).getroot()
    return {_rel(o, "audioFile") for o in root if o.get("class") == "SingleSound"}


def assign_bank(path, bank):
    text = open(path, encoding="utf-8").read()
    if '<relationship name="banks">' in text:
        return False
    head_end = text.index("\t</object>")
    insert = ('\t\t<relationship name="banks">\n\t\t\t<destination>%s</destination>\n'
              '\t\t</relationship>\n' % bank)
    text = text[:head_end] + insert + text[head_end:]
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    return True


def ensure_buses(proj, dry):
    """Creates the Music and SFX buses under the master bus if missing."""
    made = []
    for name in sorted(set(BUSES.values())):
        if name in proj.groups:
            continue
        gid, chain, fader, pan = guid(), guid(), guid(), guid()
        proj.groups[name] = gid
        made.append(name)
        if dry:
            continue
        doc = Doc(proj.model)
        g = doc.obj("MixerGroup", gid, name=name)
        rel(g, "effectChain", chain)
        rel(g, "panner", pan)
        rel(g, "output", proj.master_bus)
        rel(doc.obj("MixerBusEffectChain", chain), "effects", fader)
        doc.obj("MixerBusPanner", pan)
        doc.obj("MixerBusFader", fader)
        os.makedirs(os.path.join(proj.meta, "Group"), exist_ok=True)
        doc.write(os.path.join(proj.meta, "Group", "%s.xml" % gid))
    for name in made:
        print("   bus      %s" % name)
    return made


def route_events(proj, dry):
    """Points every event that feeds the master bus directly at its bus.
    An event already routed somewhere else was routed on purpose; it stays."""
    moved = 0
    for path, f in sorted(proj.events.items()):
        bus = bus_for(proj, path)
        if bus == proj.master_bus:
            continue
        text = open(f, encoding="utf-8").read()
        m = re.search(r'(<object class="MixerInput" id="\{[^}]+\}">.*?<relationship name="output">'
                      r'\s*<destination>)(\{[^}]+\})', text, re.S)
        if not m or m.group(2) != proj.master_bus:
            continue
        moved += 1
        if not dry:
            text = text[:m.start(2)] + bus + text[m.end(2):]
            with open(f, "w", encoding="utf-8", newline="\n") as fh:
                fh.write(text)
    print("%s %d events onto the Music and SFX buses" % ("would route" if dry else "routed", moved))


def apply(proj, work, dry):
    sound, music = proj.banks.get("Sound"), proj.banks.get("Music")
    if not (sound and music):
        raise SystemExit("the project needs a Sound bank and a Music bank")
    new_folders = []
    made = replaced = assigned = kept = 0
    for path, kind, payload, replace in work:
        bank = sound if path.startswith("SFX/") else music
        existing = proj.events.get(path)
        if kind == "assign" or (existing and not replace):
            if existing is None:
                print("  !! %s: no such event to assign" % path)
                continue
            if dry:
                if '<relationship name="banks">' not in open(existing, encoding="utf-8").read():
                    print("   bank     %s" % path)
                    assigned += 1
            elif assign_bank(existing, bank):
                assigned += 1
                print("   bank     %s" % path)
            else:
                kept += 1
            continue

        if existing:
            eid, folder, old_bank, tuned = existing_state(existing)
            if tuned:
                print("  !! %s is hand-tuned (%s) - not replacing" % (path, ", ".join(tuned)))
                continue
            bank = old_bank or bank
            target = existing
            if kind == "sfx" and _clips_of(existing) == {proj.audio[c][0] for c in payload}:
                kept += 1
                continue        # already exactly this; rebuilding only churns ids
        else:
            *dirs, _ = path.split("/")
            eid = guid()
            folder = proj.folder_for(dirs, new_folders)
            target = os.path.join(proj.meta, "Event", "%s.xml" % eid)
        name = path.split("/")[-1]

        if kind in ("sfx", "music_oneshot"):
            doc = action_sheet_event(proj, path, eid, name, folder, bank, payload)
            what = "%d clip%s" % (len(payload), "" if len(payload) == 1 else "s")
        elif kind == "music_loop":
            seg = [{"clip": payload[0], "start": 0.0, "loop": True}]
            doc = timeline_event(proj, path, eid, name, folder, bank, seg)
            what = "loop"
        else:
            doc = timeline_event(proj, path, eid, name, folder, bank, payload)
            what = "%d phases" % sum(1 for s in payload if s.get("loop"))
        print("   %-8s %-40s %s" % ("replace" if existing else "new", path, what))
        if not dry:
            doc.write(target)
            proj.events[path] = target
        replaced += bool(existing)
        made += not existing

    if not dry:
        for fid, name, parent in new_folders:
            d = Doc(proj.model)
            f = d.obj("EventFolder", fid, name=name)
            rel(f, "folder", parent)
            d.write(os.path.join(proj.meta, "EventFolder", "%s.xml" % fid))
    print("\n%s %d new events, %d replaced, %d newly banked, %d folders"
          % ("would write" if dry else "wrote", made, replaced, assigned, len(new_folders)))


def stream_map(proj):
    """catalog id -> {streams: [res:// paths], loop: bool} for the Godot backend.

    One-shots play any of their clips. A lawn's music plays its first wave's
    loop - the fallback has no phases - and anything with a loop region loops.
    """
    catalog = json.load(open(CATALOG, encoding="utf-8"))["events"]
    out = {}
    for entry in catalog:
        fmod = entry.get("fmod", "")
        path = proj.events.get(fmod[len("event:/"):]) if fmod.startswith("event:/") else None
        if path is None:
            continue
        root = ET.parse(path).getroot()
        by_id = {o.get("id"): o for o in root}
        audio_ids = {v[0]: k for k, v in proj.audio.items()}
        sounds = [o for o in root if o.get("class") == "SingleSound"]
        regions = [o for o in root if o.get("class") == "LoopRegion"]
        clips = [audio_ids.get(_rel(s, "audioFile")) for s in sounds]
        clips = [c for c in clips if c]
        if not clips:
            continue
        loop = (bool(regions) or any(_prop(s, "isLooping") == "true" for s in sounds)
                or any(o.get("class") == "MultiSound" and _prop(o, "looping") == "true"
                       for o in root))
        if regions and len(sounds) > 1:
            # Prefer the first wave's loop, then the final one - the fallback
            # has no phases, so it plays the lawn's own music, never the
            # seed chooser's.
            starts = {round(float(_prop(s, "start") or 0), 2): audio_ids.get(_rel(s, "audioFile"))
                      for s in sounds}
            named = {_prop(r, "name"): round(float(_prop(r, "position") or 0), 2)
                     for r in regions if _prop(r, "name")}
            pick = None
            for label in ("First Wave", "Final Wave"):
                if label in named:
                    # The region opens on the intro, if there is one; the loop
                    # is the last sound that starts inside it.
                    pos = named[label]
                    inside = sorted(t for t in starts if t >= pos - 0.01)
                    later = [t for t in inside
                             if not any(pos < r <= t for r in named.values() if r != pos)]
                    if later:
                        pick = starts[later[-1]]
                        break
            clips = [pick or clips[0]]
        out[entry["id"]] = {"streams": [STREAM_ROOT + c for c in clips]}
        if loop:
            out[entry["id"]]["loop"] = True
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        print(__doc__)
        return 2
    proj = Project(args[0])
    if "--streams" in sys.argv:
        out = sys.argv[sys.argv.index("--streams") + 1]
        data = {"//": "Generated by tools/fmod_build_content.py --streams from the Studio "
                      "project. The clips each event plays, for the Godot fallback backend "
                      "when FMOD is not installed. Do not edit by hand.",
                "streams": stream_map(proj)}
        with open(out, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(data, fh, indent=1, sort_keys=True)
            fh.write("\n")
        print("wrote %d stream entries to %s" % (len(data["streams"]), out))
        return 0

    content = json.load(open(CONTENT, encoding="utf-8"))
    music_map = json.load(open(MUSIC_MAP, encoding="utf-8"))
    try:
        work = plan(proj, content, music_map)
    except KeyError as e:
        print("!! %s" % e.args[0], file=sys.stderr)
        return 1
    print("project: %d events, %d clips" % (len(proj.events), len(proj.audio)))
    dry = "--dry-run" in sys.argv
    ensure_buses(proj, dry)
    apply(proj, work, dry)
    route_events(proj, dry)

    missing = {k: v for k, v in catalog_ids(music_map).items()}
    have = {e["id"] for e in json.load(open(CATALOG, encoding="utf-8"))["events"]}
    todo = sorted(k for k in missing if k not in have)
    if todo:
        print("\ncatalog ids with an event but no catalog entry: %s" % ", ".join(todo))
    return 0


if __name__ == "__main__":
    sys.exit(main())
