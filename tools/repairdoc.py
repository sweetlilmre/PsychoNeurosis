"""Repair a markdown document whose line breaks have been multiplied.

    python tools/repairdoc.py docs/README.md            report, change nothing
    python tools/repairdoc.py docs/README.md --write     apply the repair

WHAT THE DAMAGE IS. Some tool in this environment has, on at least two
occasions, rewritten a markdown file with every line break multiplied -- and
the multiplier is NOT uniform across the file. `VangeliSTracker`'s `00-map.md`
came out at 91% blank lines with multipliers from 16 down to 1; this repo's
`docs/README.md` came out at 58% with a multiplier of mostly 2. The cause has
never been identified, which is exactly why this is a tool and not a one-shot.

WHY ARITHMETIC ALONE CANNOT UNDO IT. A single global divisor does not exist:
in the worst case table rows sat 16, 5, 12, 7, 4, 9, 1 and 2 blank lines apart
for what must all have been adjacency. The multiplier looks per-line, as though
each rewrite reset the padding of the lines it touched.

WHAT DOES WORK, and it is the whole trick:

  * Within a run of consecutive PROSE lines the multiplier IS constant, so the
    original gap is `gap // min(gaps in the run)`. In `00-map.md` this held for
    70 of 71 runs, quotients 1..3.
  * Tables, fenced blocks and indented code need no multiplier at all. Markdown
    forbids a blank line inside a table, and the rest read as one block.
  * A prose adjacency with no run to infer from falls back to punctuation: a
    line not ending in `.:!?` was wrapped mid-sentence, so its successor
    belongs to the same paragraph.

The repair is verifiable rather than tasteful, and the script proves it before
writing: every non-blank line must be identical in content and order, and every
non-whitespace character must be identical. It refuses to write if not.

It also reverses cp1252-as-UTF-8 mojibake, which travelled with the same
damage: an em dash read as cp1252 becomes three characters, and the reversal is
exact.
"""
import argparse
import collections
import pathlib
import re
import sys

# each of these is a UTF-8 sequence that was decoded as cp1252 and re-encoded
MOJIBAKE = [
    ('â€”', '—'),   # em dash
    ('â€“', '–'),   # en dash
    ('â€™', '’'),   # right single quote
    ('â€œ', '“'),   # left double quote
    ('Ã³', 'ó'),
    ('Ã¡', 'á'),
    ('Ã©', 'é'),
    ('Ã±', 'ñ'),
    ('Â©', '©'),
    ('Â¡', '¡'),
    ('Â¿', '¿'),
]


def classify(content):
    """Tag every content line, so structure can supply the gaps arithmetic cannot."""
    kinds, fence = [], False
    for line in content:
        if line.lstrip().startswith('```'):
            kinds.append('fence')
            fence = not fence
            continue
        if fence:
            kinds.append('fence')
        elif line.startswith('#'):
            kinds.append('head')
        elif line.strip() in ('---', '***', '___'):
            kinds.append('rule')
        elif line.startswith('|'):
            kinds.append('table')
        elif line.startswith('    ') or line.startswith('\t'):
            kinds.append('code')
        elif re.match(r'^\s*([-*+]|\d+\.)\s', line):
            kinds.append('list')
        elif line.startswith('>'):
            kinds.append('quote')
        else:
            kinds.append('prose')
    return kinds


def segment(run, gaps):
    """Split a run of gap indices into maximal blocks one constant multiplier explains."""
    out, i = [], 0
    while i < len(run):
        chosen = None
        for j in range(len(run), i, -1):
            g = [gaps[x] for x in run[i:j]]
            m = min(g)
            if all(x % m == 0 and x // m <= 3 for x in g):
                chosen = (j, m)
                break
        if chosen is None:                      # a lone gap explains itself
            chosen = (i + 1, gaps[run[i]])
        out.append((run[i:chosen[0]], chosen[1]))
        i = chosen[0]
    return out


def repair(text):
    """Return (repaired text, report). Does not write."""
    report = collections.Counter()

    for bad, good in MOJIBAKE:
        report['mojibake'] += text.count(bad)
        text = text.replace(bad, good)

    lines = text.split('\n')
    content = [l for l in lines if l.strip()]
    if not content:
        return text, report
    idx = [i for i, l in enumerate(lines) if l.strip()]
    gaps = [b - a for a, b in zip(idx, idx[1:])]
    kinds = classify(content)

    resolved = {}

    # prose runs: the multiplier is constant inside one, so gap//m is exact
    runs, cur = [], []
    for i in range(len(gaps)):
        if kinds[i] == 'prose' and kinds[i + 1] == 'prose':
            cur.append(i)
        else:
            if cur:
                runs.append(cur)
            cur = []
    if cur:
        runs.append(cur)
    for run in runs:
        if len(run) == 1:
            continue                            # no neighbours; punctuation decides below
        for block, m in segment(run, gaps):
            for i in block:
                resolved[i] = (gaps[i] // m, 'exact')

    # everything else: markdown leaves no choice, or punctuation decides
    for i in range(len(gaps)):
        if i in resolved:
            continue
        a, b = kinds[i], kinds[i + 1]
        if a == b and a in ('table', 'fence', 'code', 'list'):
            resolved[i] = (1, 'structural')
        elif a != b or a in ('head', 'rule') or b in ('head', 'rule'):
            resolved[i] = (2, 'structural')
        else:
            ends = content[i].rstrip().endswith(('.', ':', '!', '?'))
            resolved[i] = (2 if ends else 1, 'sentence')

    parts = [content[0]]
    for i in range(len(gaps)):
        parts.append('\n' * resolved[i][0])
        parts.append(content[i + 1])
    out = ''.join(parts).rstrip('\n') + '\n'

    for _, how in resolved.values():
        report[how] += 1
    report['lines_before'] = len(lines)
    report['lines_after'] = out.count('\n')
    report['content_lines'] = len(content)
    return out, report


def prove(before, after):
    """The repair must move blank lines and nothing else. Returns a list of failures."""
    fixed = before
    for bad, good in MOJIBAKE:
        fixed = fixed.replace(bad, good)
    bad = []
    a = [l for l in fixed.split('\n') if l.strip()]
    b = [l for l in after.split('\n') if l.strip()]
    if a != b:
        where = next((i for i, (x, y) in enumerate(zip(a, b)) if x != y), min(len(a), len(b)))
        bad.append('non-blank lines differ (%d vs %d), first at %d' % (len(a), len(b), where))
    if ''.join(fixed.split()) != ''.join(after.split()):
        bad.append('non-whitespace characters differ')
    if '\n\n\n' in after:
        bad.append('a run of more than one blank line survived')
    return bad


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('path')
    ap.add_argument('--write', action='store_true', help='apply the repair')
    args = ap.parse_args()

    p = pathlib.Path(args.path)
    raw = p.read_bytes()
    # preserve the file's own line ending: this repo's docs are CRLF, and a
    # silent conversion is exactly the kind of unasked-for change to avoid
    eol = '\r\n' if raw.count(b'\r\n') > raw.count(b'\n') // 2 else '\n'
    before = raw.decode('utf-8').replace('\r\n', '\n')
    lines = before.split('\n')
    blank = sum(1 for l in lines if not l.strip())
    pct = 100.0 * blank / max(len(lines), 1)
    print('%s: %d lines, %d blank (%.1f%%)' % (p, len(lines), blank, pct))
    if pct < 45 and not any(m in before for m, _ in MOJIBAKE):
        print('looks undamaged -- nothing to do')
        return 0

    after, report = repair(before)
    print('  mojibake reversed   %d' % report['mojibake'])
    print('  gaps exact          %d  (a clean multiplier inside a prose run)' % report['exact'])
    print('  gaps structural     %d  (markdown leaves no choice)' % report['structural'])
    print('  gaps by punctuation %d  (a lone prose adjacency)' % report['sentence'])
    print('  %d content lines, %d lines -> %d'
          % (report['content_lines'], report['lines_before'], report['lines_after']))

    failures = prove(before, after)
    if failures:
        print('\nREFUSING TO WRITE -- the repair changed content:')
        for f in failures:
            print('  ! %s' % f)
        return 1
    print('  proof: every non-blank line and every non-whitespace character identical')

    if args.write:
        p.write_text(after, encoding='utf-8', newline=eol)
        print('\nwritten (%s line endings, as found)' % ('CRLF' if eol == '\r\n' else 'LF'))
    else:
        print('\n(dry run -- pass --write to apply)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
