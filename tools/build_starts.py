#!/usr/bin/env python3
"""Build Data/Starts.lua from NeverQuest quest start exports.

Each input file is the text from /nq db export in game:

    NQQ1~<client build>~<addon version>~<questID>^<title>^<level>^<map>^<x>^<y>^<factions>^<firsthand>~...

Usage:
    python3 -I tools/build_starts.py exports/*.txt
    python3 -I tools/build_starts.py exports/*.txt --credit "Name <file.txt>" --out Data/Starts.lua

Every entry here was seen in the live game by NeverQuest's own scan. Nothing is converted
from another addon, database project or website.

When contributors disagree about where a quest starts, the position most of them agree on
wins: positions within AGREE of each other count as the same spot, and the best backed group
takes it. A single contributor's entry is kept as-is, since one report beats none.

A place the sender's own client saw counts for more than one they were told about by another
player, because sharing means the same original sighting can reach us several times over. Only
first-hand reports are counted when deciding how much agreement a position really has.
"""

import argparse
import re
import sys
from collections import Counter, defaultdict
from datetime import date
from pathlib import Path

AGREE = 0.02          # map fractions: positions this close are the same spot
MAX_TITLE = 120


def has_firsthand_field(text):
    """Does this export carry the first-hand flag at all?

    The flag arrived after the first exports did, and absence of a flag on one record is
    ambiguous: it could mean relayed, or it could mean the export predates the field. Deciding
    per file removes the ambiguity. If no record in the file has the field, the file is older
    than the field and every place in it was the sender's own, since relaying at any scale came
    in with the same release.
    """
    for record in re.sub(r"[\r\n\t]", "", text).strip().split("~")[3:]:
        if record and len(record.split("^")) > 7:
            return True
    return False


def parse(text, flagged=None):
    """Yield (qid, title, level, map, x, y, factions, firsthand, zone) from one export blob.

    A record with no place (a quest known by name only, from /nq db harvest) has map, x and y
    as None. zone is the map the game files the quest under, or None.
    """
    if flagged is None:
        flagged = has_firsthand_field(text)
    text = re.sub(r"[\r\n\t]", "", text).strip()
    if not text.startswith("NQQ1"):
        raise ValueError("not a NeverQuest quest start export (should start with NQQ1~)")
    records = text.split("~")
    for record in records[3:]:     # 1 the tag, 2 the client build, 3 the addon version
        if not record:
            continue
        f = record.split("^")
        if len(f) < 6:
            continue
        bare = f[3] == "" and f[4] == "" and f[5] == ""
        try:
            qid = int(f[0])
            if bare:
                m = x = y = None
            else:
                m, x, y = int(f[3]), float(f[4]), float(f[5])
        except ValueError:
            continue
        title = f[1].strip()[:MAX_TITLE]
        if not title or qid <= 0:
            continue
        if not bare:
            if m <= 0:
                continue
            if not (0.0 <= x <= 1.0 and 0.0 <= y <= 1.0) or (x == 0.0 and y == 0.0):
                continue
        try:
            level = int(f[2]) if f[2] else None
        except ValueError:
            level = None
        if level is not None and not (0 < level < 200):
            level = None
        factions = "".join(sorted({c for c in (f[6] if len(f) > 6 else "") if c in "AHN"}))
        firsthand = (f[7].strip() == "1") if (flagged and len(f) > 7) else not flagged
        try:
            zone = int(f[8]) if len(f) > 8 and f[8] else None
        except ValueError:
            zone = None
        yield qid, title, level, m, x, y, factions, firsthand, (zone if zone and zone > 0 else None)


def agreed_spot(spots):
    """The best backed position, as (map, x, y, firsthand_votes, total_reports).

    Groups positions that are within AGREE of each other, then picks the group with the most
    first-hand reports, falling back to the largest group. Relayed copies still contribute
    their position to the average but never to the agreement count, since several of them can
    descend from one original sighting.
    """
    best, best_group, best_key = None, [], (-1, -1)
    for anchor in spots:
        m0, x0, y0 = anchor[0], anchor[1], anchor[2]
        group = [s for s in spots if s[0] == m0 and abs(s[1] - x0) <= AGREE and abs(s[2] - y0) <= AGREE]
        first = sum(1 for s in group if s[3])
        key = (first, len(group))
        if key > best_key:
            best, best_group, best_key = anchor, group, key
    n = len(best_group)
    # Average over first-hand reports when there are any, so a crowd of relays can't drag a
    # confirmed position off the mark.
    weigh = [s for s in best_group if s[3]] or best_group
    mx = sum(s[1] for s in weigh) / len(weigh)
    my = sum(s[2] for s in weigh) / len(weigh)
    return best[0], round(mx, 4), round(my, 4), best_key[0], len(spots)


def version_tuple(v):
    """1.18.0 -> (1, 18, 0), so versions compare sensibly and junk sorts lowest."""
    parts = re.findall(r"\d+", v or "")
    return tuple(int(p) for p in parts) if parts else (0,)


def lua_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("inputs", nargs="+", type=Path)
    ap.add_argument("--out", type=Path, default=Path("Data/Starts.lua"))
    ap.add_argument("--version", type=int, default=None, help="defaults to the old file's version plus one")
    ap.add_argument("--build", default=None, help="client build, e.g. 1.60.1 (default: from the exports)")
    ap.add_argument("--credit", action="append", default=[], help="contributor name, repeatable")
    ap.add_argument("--min-addon", default=None,
                    help="refuse exports from addon versions below this, e.g. 1.18.0")
    ap.add_argument("--report", type=Path, default=None,
                    help="write a per-quest provenance report here, for checking disputes by hand")
    args = ap.parse_args()

    titles = defaultdict(Counter)
    levels = defaultdict(Counter)
    first_titles = defaultdict(Counter)
    first_levels = defaultdict(Counter)
    spots = defaultdict(list)
    zones = defaultdict(Counter)
    factions = defaultdict(set)
    senders = defaultdict(set)
    builds = Counter()
    read = 0

    for path in args.inputs:
        text = path.read_text(encoding="utf-8", errors="replace")
        head = re.sub(r"[\r\n\t]", "", text).split("~")
        if len(head) > 1:
            builds[head[1].strip()] += 1
        addon = head[2].strip() if len(head) > 2 else ""
        if args.min_addon and version_tuple(addon) < version_tuple(args.min_addon):
            print(f"{path}: SKIPPED, addon version {addon or '?'} is below {args.min_addon}", file=sys.stderr)
            continue
        n = 0
        flagged = has_firsthand_field(text)
        if not flagged:
            print(f"{path}: no first-hand flags, treating as the sender's own sightings", file=sys.stderr)
        for qid, title, level, m, x, y, fac, firsthand, zone in parse(text, flagged):
            titles[qid][title] += 1
            if firsthand:
                first_titles[qid][title] += 1
            if level:
                levels[qid][level] += 1
                if firsthand:
                    first_levels[qid][level] += 1
            if m is not None:
                spots[qid].append((m, x, y, firsthand))
            if zone:
                zones[qid][zone] += 1
            factions[qid] |= set(fac)
            senders[qid].add(path.name)
            n += 1
        print(f"{path}: {n} records", file=sys.stderr)
        read += n

    if not titles:
        sys.exit("no usable records found")

    old_version = 0
    if args.out.exists():
        match = re.search(r"version\s*=\s*(\d+)", args.out.read_text(encoding="utf-8"))
        if match:
            old_version = int(match.group(1))
    version = args.version if args.version is not None else old_version + 1
    build = args.build or (builds.most_common(1)[0][0] if builds else "?")

    lines, report = [], []
    disputed, relayed_only = 0, 0
    placed = 0
    for qid in sorted(titles):
        has_spot = bool(spots[qid])
        if has_spot:
            placed += 1
            m, x, y, votes, total = agreed_spot(spots[qid])
            if votes < total:
                disputed += 1
            if votes == 0:
                relayed_only += 1
        # A title or level someone's own client read beats a relayed one, for the same reason
        # the position does: relays multiply copies, not evidence.
        title = (first_titles[qid] or titles[qid]).most_common(1)[0][0]
        level_votes = first_levels[qid] or levels[qid]
        if has_spot:
            report.append(
                f"{qid}\t{title}\t{m}\t{x:.4f}\t{y:.4f}"
                f"\t{votes} first-hand of {total}\t{','.join(sorted(senders[qid]))}"
            )
            fields = [f"t = {lua_string(title)}", f"m = {m}", f"x = {x:.4f}", f"y = {y:.4f}"]
        else:
            # Known by name only: a title, a level and a zone, and no place to stand.
            report.append(f"{qid}\t{title}\t\t\t\tname only\t{','.join(sorted(senders[qid]))}")
            fields = [f"t = {lua_string(title)}"]
        if zones[qid]:
            fields.append(f"zm = {zones[qid].most_common(1)[0][0]}")
        if level_votes:
            fields.insert(1, f"l = {level_votes.most_common(1)[0][0]}")
        fac = "".join(sorted(factions[qid]))
        if fac and fac != "AHN":
            fields.append(f"f = {lua_string(fac)}")
        lines.append(f"\t\t[{qid}] = {{ {', '.join(fields)} }},")

    header = args.out.read_text(encoding="utf-8").split("ns.Starts = {")[0] if args.out.exists() else ""
    if "local ADDON, ns" not in header:
        sys.exit(f"{args.out} is missing its comment header and 'local ADDON, ns = ...' line; restore it first")

    credit = ", ".join(lua_string(c) for c in args.credit)
    body = (
        f"{header}ns.Starts = {{\n"
        f"\t-- Bumped whenever this file is rebuilt. Shown by /nq db.\n"
        f"\tversion = {version},\n"
        f"\tbuild = {lua_string(build)},\n"
        f"\tgathered = {lua_string(date.today().isoformat())},\n"
        f"\t-- Contributors, by the name they asked to be credited under.\n"
        f"\tcredit = {{{credit}}},\n"
        f"\tq = {{\n"
        + "\n".join(lines)
        + "\n\t},\n}\n"
    )
    args.out.write_text(body, encoding="utf-8")
    if args.report:
        args.report.write_text(
            "questID\ttitle\tmap\tx\ty\tagreement\tfrom\n" + "\n".join(report) + "\n",
            encoding="utf-8",
        )
        print(f"wrote {args.report}: provenance for {len(report)} quests", file=sys.stderr)
    print(
        f"wrote {args.out}: {len(lines)} quests ({placed} with a place, {len(lines) - placed} by name only) "
        f"from {read} records, version {version}, "
        f"build {build}, {disputed} where contributors disagreed, "
        f"{relayed_only} with no first-hand report behind them",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
