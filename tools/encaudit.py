"""Find text I/O that relies on the locale encoding instead of stating one.

    python tools/encaudit.py                   audit this repo's tools
    python tools/encaudit.py <dir> [<dir>...]  audit somewhere else

Exit status is 1 when anything is found, so it can gate a build.

WHY THIS EXISTS. Windows' locale encoding is cp1252, so an unqualified
`open`, `read_text`, `write_text`, or a `subprocess` with text mode on,
silently decodes UTF-8 as cp1252. In this project that is not theoretical: it
mojibaked two documents, and it produced two false comparisons in one session --
once making a pure line-ending difference look like character loss, which sent a
whole investigation down the wrong path.

THE CONVENTION IT ENFORCES, which is about who reads the file:

    documents (.md)                     utf-8, and LF
    DOS files (.PAS .ASM .INC .MAP)     ascii, and CRLF on write
    our own stdout via subprocess       utf-8

`ascii` on a DOS file is a guard rather than a codec preference: it raises
instead of quietly encoding an em dash as two bytes into a file Turbo Pascal
will read, where inside a comment it could even close the comment.

WHY IT PARSES INSTEAD OF MATCHING TEXT, and this is the interesting part.
Three attempts, each failing differently, and the sequence is a small lesson in
choosing an instrument:

  a line-based regex   reported 32 sites on this tree of which 16 were
                       artifacts -- calls whose `encoding=` sat on a
                       continuation line, or which already passed
                       `encoding="ascii"` -- and MISSED 4 genuine ones. Wrong in
                       both directions at once.
  parenthesis matching fixed the continuation-line blindness, then flagged this
                       file's own docstring, because it could not tell code from
                       prose.
  the AST             sees exactly the calls that exist, with their real
                       keywords, and nothing that only looks like one.

The general form: a measuring tool that cannot see the whole structure it is
judging will both cry wolf and stay silent, and you will believe it either way.
"""
import ast
import pathlib
import sys

# call target -> the argument that must be present
# `read` is deliberately NOT here. It takes no encoding -- that belongs on the
# `open` that produced the handle -- and watching it flags every binary handle
# and every project function that happens to be called read().
WATCHED = {
    'open': 'encoding',
    'read_text': 'encoding',
    'write_text': 'encoding',
}
SUBPROCESS = ('run', 'Popen', 'check_output', 'call', 'check_call')

DEFAULT_DIRS = ('tools', 'tools/dosbox')


def target_name(node):
    """The rightmost name of a call target: foo.bar.baz( -> 'baz'."""
    f = node.func
    if isinstance(f, ast.Attribute):
        return f.attr
    if isinstance(f, ast.Name):
        return f.id
    return ''


def kwargs_of(node):
    return {k.arg for k in node.keywords if k.arg}


def is_binary(node):
    """A binary mode string among the positional args means no encoding applies."""
    for a in node.args:
        if isinstance(a, ast.Constant) and isinstance(a.value, str) and 'b' in a.value \
                and set(a.value) <= set('rwaxb+t'):
            return True
    return False


def text_mode_on(node):
    """True when a subprocess call will decode its output."""
    for k in node.keywords:
        if k.arg in ('text', 'universal_newlines'):
            if isinstance(k.value, ast.Constant) and k.value.value:
                return True
        if k.arg == 'encoding':
            return True
    return False


def audit(path):
    """Return [(line, description)] for every call that leaves the encoding to the locale."""
    raw = path.read_bytes()
    try:
        text = raw.decode('utf-8')
    except UnicodeDecodeError as e:
        return [(0, 'file is not UTF-8 (%s at byte %d) -- fix the file first'
                    % (e.reason, e.start))]
    try:
        tree = ast.parse(text, filename=str(path))
    except SyntaxError as e:
        return [(e.lineno or 0, 'does not parse: %s' % e.msg)]

    out = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        name = target_name(node)
        kw = kwargs_of(node)

        if name in SUBPROCESS and text_mode_on(node) and 'encoding' not in kw:
            out.append((node.lineno, '%s(... text mode on, no encoding=)' % name))
            continue

        if name in WATCHED and 'encoding' not in kw and not is_binary(node):
            out.append((node.lineno, '%s(... no encoding=)' % name))
    return out


def main(argv):
    root = pathlib.Path('.').resolve()
    dirs = argv[1:] or DEFAULT_DIRS
    files, findings = 0, 0
    for d in dirs:
        for p in sorted((root / d).glob('*.py')):
            files += 1
            hits = audit(p)
            if hits:
                print('  %s' % p.relative_to(root))
                for ln, what in hits:
                    print('    %4d  %s' % (ln, what))
                findings += len(hits)
    print('\n%d site(s) in %d file(s) leave the encoding to the locale'
          % (findings, files))
    if findings:
        print('State it: utf-8 for documents and our own stdout, ascii for DOS files.')
    return 1 if findings else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
