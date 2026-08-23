# How a Python toolkit is shared between two private repos

Resolves [#32](https://github.com/sweetlilmre/PsychoNeurosis/issues/32), which is the evidence ticket behind the grilling ticket [#31](https://github.com/sweetlilmre/PsychoNeurosis/issues/31). **No winner is picked here** — that is #31's job. This document establishes what each mechanism costs and, for the constraint that actually binds in this repo, whether it can keep every machine-specific absolute path out of every committed file.

Every claim is tagged **DOCUMENTED** (a primary source says it, cited), **MEASURED** (this session ran it on this machine, `uv 0.11.15`, `git 2.55.0.windows.3`, Windows 11), or **INFERRED**. The measurements exist because three of the questions #32 asks are *not answered by the documentation at all* — most importantly what `uv.lock` records for a path source, and what happens when the other checkout is missing. A measurement beats an argument, and here the argument had no documentation to stand on.

## 0. The finding that comes before all the options

**The toolkit is not installable today, by any of these mechanisms.** MEASURED: the command `CLAUDE.md` documents,

    uv pip install --python .venv/Scripts/python.exe -e kit/tools

fails, and has presumably always failed:

    Call to `setuptools.build_meta:__legacy__.build_editable` failed (exit code: 1)
    error: Multiple top-level packages discovered in a flat-layout:
    ['pascal', 'substrate', 'wikitools'].

MEASURED: `kit/tools/pyproject.toml` declares no `[build-system]` and no package list, and there is no `__init__.py` anywhere under `kit/tools/`. MEASURED: `.venv/Lib/site-packages` in this working tree contains `pyyaml`, `capstone` and nothing else — no `pascal_re_toolkit-0.1.0.dist-info`, no `__editable__` path file. The toolkit has never been installed into it.

Nothing is broken by this, because every documented invocation runs a script *by path* (`kit/tools/wikitools/okfcheck.py`), and Python puts the script's own directory on `sys.path`, so the scripts never import each other across subdirectories. MEASURED: `okfcheck.py` imports only `io`, `pathlib`, `sys` and `yaml`.

The consequence for #31 is the important part: **"the toolkit already has a `pyproject.toml` and is installed editable into `.venv` with `uv`" is half true.** The `pyproject.toml` exists; the editable install does not, and cannot until the package grows a build backend and an explicit package layout. Every option below except vendoring and bare `PYTHONPATH` needs that work done first, so it is a shared prerequisite cost rather than a discriminator between the options. It is roughly: add `[build-system]`, choose flat-layout with an explicit `packages` list or move to `src/`, add `__init__.py` files, and decide whether the three subdirectories are one distribution or three. MEASURED: adding `[build-system]` plus `[tool.setuptools] packages = ["pascal", "substrate", "wikitools"]` and three empty `__init__.py` files was sufficient to make every measurement in this document possible.

## 1. Editable install from a local path

### What it is

DOCUMENTED: pip describes an editable install as installing "your project without copying any files. Instead, the files in the development directory are added to Python's import path" ([pip local project installs](https://pip.pypa.io/en/stable/topics/local-project-installs/)). The mechanism is [PEP 660](https://peps.python.org/pep-0660/): "Build backends must populate the generated wheel with files that when installed will result in an editable install," and backends "may choose to place a `.pth` file at the root of the `.whl` file, containing the root directory of the source tree."

MEASURED: with setuptools as the backend, `uv pip install -e <dir>` writes three things into `site-packages` — `__editable__.pascal_re_toolkit-0.1.0.pth` (a one-line `import` of a finder module), `__editable___pascal_re_toolkit_0_1_0_finder.py`, and a `dist-info` directory. The finder carries an **absolute path per top-level package**:

    MAPPING: dict[str, str] = {'pascal': 'C:\\...\\tk\\pascal', 'substrate': ..., 'wikitools': ...}

and `dist-info/direct_url.json` records `{"url":"file:///C:/.../tk","dir_info":{"editable":true}}`.

DOCUMENTED: that absolute path is required, not incidental. The [direct URL data structure](https://packaging.python.org/en/latest/specifications/direct-url-data-structure/) specification states: "When `url` refers to a local directory, it MUST have the `file` scheme and be compliant with RFC 8089. In particular, the path component must be absolute."

### What happens when the other repo is not checked out

MEASURED: moving the source directory away and importing gives no warning about a dangling install — just `ModuleNotFoundError: No module named 'wikitools'`. The `.pth`, the finder and the `dist-info` all remain in place, so `uv pip list` still reports the package as installed. DOCUMENTED gap: PEP 660 says nothing whatsoever about a moved or deleted source tree.

### The absolute-path question

**It keeps every machine path out of every committed file, as long as the install is done by a command rather than declared in a file.** MEASURED: every absolute path lands inside `.venv`, and `.venv/` is git-ignored in both repos — line 42 of this repo's `.gitignore`, lines 12–13 of the sibling's. The path is supplied on the command line each time, exactly as `census.py` already takes the sibling repo's location as an argument.

### Cost

**Setup:** the section 0 prerequisite, then one command per consumer venv. **Upkeep:** near zero while both checkouts exist — an edit in `kit/tools/` is live in both venvs with no reinstall, which is the whole point. Against that, the command is undiscoverable: nothing in the consumer repo records that the install is needed or where the toolkit lives, so it has to be written into the entry stanza as a human instruction. A fresh clone has a venv that imports nothing until somebody remembers to run it, and the failure mode is a bare `ModuleNotFoundError`.

## 2. Declared path dependency — `[tool.uv.sources]`

### What it is

DOCUMENTED: uv's [dependencies concept page](https://docs.astral.sh/uv/concepts/projects/dependencies/) documents `bar = { path = "../projects/bar", editable = true }` and states "path may also be a relative path." Also documented there, and load-bearing for #31: "**Sources are only respected by uv.** If another tool is used, only the definitions in the standard project tables will be used" — so a `tool.uv.sources` entry is a uv-only override, and is ignored when the package is itself consumed as somebody else's dependency.

### The absolute-path question, measured

This is the question the documentation does not answer — the uv docs are silent on whether `uv.lock` normalises a path source to absolute. MEASURED, and the answer is favourable: **`uv.lock` records the relative path verbatim.** A consumer with `pascal-re-toolkit = { path = "../tk", editable = true }` locks as

    source = { editable = "../tk" }
    requires-dist = [{ name = "pascal-re-toolkit", editable = "../tk" }]

with no absolute path anywhere in the lockfile. So a *relative* path dependency keeps machine paths out of committed files — but only by committing a hard assumption about the **relative layout of the two checkouts on disk** (`D:/source/psycho` beside `D:/source/VangeliSTracker`). That is not a machine path in the letter of the constraint, and it is arguably one in spirit: it is a committed fact about one developer's directory tree. An *absolute* path in `tool.uv.sources` violates the constraint outright.

### What happens when the other repo is not checked out

MEASURED, and this is the decisive cost: **a hard failure of the whole sync, not a skipped dependency.**

    error: Failed to generate package metadata for `pascal-re-toolkit==0.1.0 @ editable+../tk`
      Caused by: Distribution not found at: file:///C:/.../tk

MEASURED: the same error comes from `uv lock` as well as `uv sync`, so the resolver — not just the installer — needs the sibling checkout present. MEASURED: **moving the dependency into an optional `[dependency-groups]` table does not help.** Even `uv sync --no-group toolkit` fails with `Distribution not found`, because locking covers every group regardless of what is being installed. This directly contradicts #31's constraint that the answer "has to survive somebody working on only one of the two repositories, with the other not checked out": a declared path dependency does not survive it, and there is no documented switch that makes it survive.

### Workspaces

DOCUMENTED: uv's [workspaces page](https://docs.astral.sh/uv/concepts/projects/workspaces/) says "Every workspace needs a root, which is *also* a workspace member," that `members` accepts globs, and that every matched directory "must contain a `pyproject.toml` file." It never states whether a member may live outside the root's directory tree — every example is a subdirectory. MEASURED: **it may.** A root with `members = ["../tk"]` and `pascal-re-toolkit = { workspace = true }` resolves, locks as `source = { editable = "../tk" }`, syncs, and imports successfully. So the undocumented answer is that uv permits it — but it inherits exactly the same relative-layout assumption and the same hard failure when the sibling is absent, and it additionally makes the sibling repo a member of this repo's workspace, which is a strange thing for two independent private repositories to be.

### Cost

**Setup:** section 0, plus a few committed lines. **Upkeep:** zero while both checkouts exist and are laid out as assumed — `uv sync` does the whole job, and the mechanism is self-documenting in a way option 1 is not. The cost is entirely in the two failure modes: a committed relative-layout assumption, and a total inability to work on one repo alone.

## 3. Git dependency

### What it is

DOCUMENTED: uv supports `git+https://` requirements with `@tag`, `@branch` or a commit hash for `uv pip install`, and `git =` with `tag =` / `branch =` / `rev =` keys under `[tool.uv.sources]` ([dependencies](https://docs.astral.sh/uv/concepts/projects/dependencies/), [uv pip packages](https://docs.astral.sh/uv/pip/packages/)).

**Subdirectory support matters here**, because the toolkit is at `kit/tools/` and not at the repo root. DOCUMENTED: uv supports it — `{ git = "...", subdirectory = "libs/langchain" }`, and "A `subdirectory` may be specified if the package isn't in the repository root" ([dependencies](https://docs.astral.sh/uv/concepts/projects/dependencies/)). pip has the same feature: "Pip looks at the `subdirectory` fragments of VCS URLs for specifying the path to the Python package, when it is not in the root of the VCS directory" ([pip VCS support](https://pip.pypa.io/en/stable/topics/vcs-support/)). DOCUMENTED: `subdirectory` is **not** part of [PEP 508](https://packaging.python.org/en/latest/specifications/dependency-specifiers/) — it is a pip/uv convention layered on PEP 508's URL grammar.

### Authentication for a private repo

DOCUMENTED: uv's [git authentication page](https://docs.astral.sh/uv/concepts/authentication/git/) states "Git credential helpers are used to store and retrieve Git credentials," and that for GitHub "the simplest way to set up a credential helper is to install the `gh` CLI and use: `gh auth login`". A token in the URL is documented as `git+https://<user>:<token>@<hostname>/...`. Crucially for the no-machine-path constraint, uv protects against committing a secret: "When using `uv add`, uv *will not* persist Git credentials to the `pyproject.toml` or `uv.lock`" — a `--raw` flag overrides this, and the docs "strongly recommend setting up a credential helper instead."

`gh auth login` is already done in this environment, since `gh issue view` works. DOCUMENTED gap: the page does not name Git Credential Manager on Windows, and does not state whether uv shells out to `git` (and therefore inherits the OS credential helper) or speaks the protocol itself.

### The trap, measured

A private repo with no server is not the only shape this option takes — the two checkouts are on one disk, so `git+file://` is the obvious no-server form. MEASURED: **it crashes uv.** The natural URL panics the resolver:

    uv pip install "pascal-re-toolkit @ git+file:///C:/path/to/repo#subdirectory=toolkit"
    thread 'uv-resolver' panicked at crates/uv-pypi-types/src/parsed_url.rs:535:14:
    Git URL is invalid: AmbiguousAuthority("git+file:***@2496fc04...")

The drive-letter colon is parsed as a `user:password` authority. MEASURED: `git+file://localhost/C:/...` panics identically, and **percent-encoding the colon works** — `git+file:///C%3A/path/to/repo#subdirectory=toolkit` installs cleanly. So the local-git-URL variant is available but sits on an undocumented workaround around a hard crash, which is a poor thing to write into an entry stanza a new project follows.

### Editable git dependencies

DOCUMENTED gap: uv documents `editable = true` for `path` and workspace sources only; no example combines `git =` with `editable = true`. Treat an editable git dependency as **not documented as supported** for uv — an absence of a stated feature, not a stated prohibition. pip does document a related behaviour for VCS installs, cloning into `<venv>/src/SomeProject` ([pip VCS support](https://pip.pypa.io/en/stable/topics/vcs-support/)), but that is pip's behaviour and was not confirmed for uv.

### The absolute-path question

**A remote git URL keeps every machine path out of every committed file, and is the only option that does so without also committing an assumption about the disk layout.** A `git+file://` URL does not — it commits a drive letter.

### Cost

**Setup:** section 0, then one committed dependency line plus a credential helper that already exists. **Upkeep:** this is where it is paid. A git dependency pins a ref, so a toolkit change reaches a consumer only after a push and an explicit bump-and-relock in the consumer — no editable liveness at all, and two repos to commit to for every toolkit edit. Working on one repo alone is fine (the dependency resolves from the remote, not from a sibling checkout), which is the one thing options 2 and 4 cannot do.

## 4. git submodule

### The commands

DOCUMENTED, all from [git-submodule](https://git-scm.com/docs/git-submodule), [gitsubmodules](https://git-scm.com/docs/gitsubmodules), [gitmodules](https://git-scm.com/docs/gitmodules), [git-clone](https://git-scm.com/docs/git-clone), [git-push](https://git-scm.com/docs/git-push) and [Pro Git 7.11](https://git-scm.com/book/en/v2/Git-Tools-Submodules):

`git submodule add <repository> <path>` — "Add the given repository as a submodule at the given path to the changeset to be committed next to the current project: the current project is termed the 'superproject'."

`git clone --recurse-submodules` — "After the clone is created, initialize and clone submodules within based on the provided `<pathspec>`... This is equivalent to running `git submodule update --init --recursive <pathspec>` immediately after the clone is finished." Without the flag, `git clone` "does not populate submodule working trees."

`git submodule update --init --recursive` for an already-cloned superproject; `git submodule update --remote` to move to the tip of the tracked branch — "Instead of using the superproject's recorded SHA-1 to update the submodule, use the status of the submodule's remote-tracking branch," which "fetches the submodule's remote repository before calculating the SHA-1." The branch comes from `submodule.<name>.branch`, which "defaults to the remote HEAD."

### The absolute-path question

DOCUMENTED, and this is the exact wording that decides it: `<repository>` "may be either an absolute URL, or (if it begins with `./` or `../`), the location relative to the superproject's default remote repository" ([git-submodule](https://git-scm.com/docs/git-submodule); [gitmodules](https://git-scm.com/docs/gitmodules) repeats it). Whatever string is passed is what lands in the tracked `.gitmodules` file — git does not normalise or strip it.

DOCUMENTED: the only other thing committed is a **gitlink** in the superproject's tree, which "contains the object name of the commit that the superproject expects the submodule's working directory to be at" ([gitsubmodules](https://git-scm.com/docs/gitsubmodules)) — a bare commit SHA, never a path.

So: **a submodule with a normal remote URL keeps every machine path out of every committed file. A submodule added with a `file://D:/...` URL commits a drive letter into `.gitmodules`, verbatim.** The mechanics do not protect against that on your behalf.

### How an update propagates

DOCUMENTED, A to B: change the submodule's checkout, then `git add <path>` and commit in the superproject to record the new gitlink. Pro Git's own read-only workflow is exactly `git submodule add`, `git -C <path> checkout <new-version>`, `git add <path>`, `git commit`.

DOCUMENTED, B back to A: possible but the sharp edge of the whole mechanism. The default state is detached HEAD — "the commit recorded in the superproject will be checked out in the submodule on a detached HEAD" — and Pro Git spells out the consequence: "there is no local working branch... even if you commit changes to the submodule, those changes will quite possibly be lost the next time you run `git submodule update`." Pushing is done from the superproject with `git push --recurse-submodules=<mode>`, where `check` "will verify that all submodule commits that changed in the revisions to be pushed are available on at least one remote of the submodule. If any commits are missing the push will be aborted," and `on-demand` pushes them for you.

### Documented failure modes

DOCUMENTED, each from the sources above: detached HEAD by default; losing submodule commits to the next `update`; forgetting to commit the gitlink, which Pro Git frames as "other people who try to check out our changes are going to be in trouble since they will have no way to get the submodule changes that are depended on"; `git pull` fetching but **not updating** submodule working trees unless `--recurse-submodules` is passed or `submodule.recurse` is set true; removal needing `git rm` and not just `git submodule deinit` ("If you really want to remove a submodule from the repository and commit that use `git-rm` instead"); and branch switching being "tricky with Git versions older than Git 2.13."

INFERRED (the git docs do not say it): cloning a private submodule needs credentials for the submodule's own URL at clone and update time, because `--recurse-submodules` runs `git submodule update`, which clones that URL like any other.

### Cost

**Setup:** one `git submodule add` in each consumer, plus section 0 on top — a submodule places files, it does not make them importable. **Upkeep:** the highest of any option, and structural rather than occasional. Every toolkit edit made from inside a consumer's submodule tree is a detached-HEAD commit that must be pushed to the toolkit's own remote *and* recorded as a gitlink bump in the superproject, or it is silently lost. `git pull` not updating submodule contents by default is the classic quiet staleness. Working on one repo alone is fine — the submodule is a real checkout inside it. Note that a submodule presupposes the toolkit is **its own repository**, which is #31's fifth candidate: `kit/tools/` cannot be a submodule of the sibling while remaining an ordinary directory of this repo.

## 5. git subtree

### The commands

DOCUMENTED, from [contrib/subtree/git-subtree.adoc](https://raw.githubusercontent.com/git/git/master/contrib/subtree/git-subtree.adoc) — note that [git-scm.com/docs/git-subtree](https://git-scm.com/docs/git-subtree) **returns 404**, because subtree lives in git's `contrib/` tree and is not part of the distributed man-page set:

    git subtree -P <prefix> add  <repository> <remote-ref>
    git subtree -P <prefix> pull <repository> <remote-ref>
    git subtree -P <prefix> push <repository> [<local-commit>:]<remote-ref>
    git subtree -P <prefix> split [<local-commit>]

DOCUMENTED: what gets committed is real files and nothing else — subtrees "do not need any special constructions (like `.gitmodules` files or gitlinks) be present in your repository." Bidirectional by design: "If the standalone library gets updated, you can automatically merge the changes into your project; if you update the library inside your project, you can 'split' the changes back out again and merge them back into the library project."

### The absolute-path question

**It keeps every machine path out of every committed file, trivially and unconditionally** — the repository URL is a command-line argument to `add`/`pull`/`push` and is never recorded in a tracked file at all. This is the strongest position of any option on the binding constraint, and it is the mirror image of its weakness: nothing in the consumer repo records where the toolkit came from.

### Documented caveats

DOCUMENTED: `--squash` "produces only a single commit that contains all the differences you want to merge, rather than merging complete history," and "also helps avoid problems when the same subproject is included multiple times in the same project, or is removed and then re-added" — but consistency is on you: "Whenever you split, you need to use the same `<annotation>`, or else you don't have a guarantee that the new re-created history will be identical to the old one." `split` "produces a new, synthetic project history," and `--rejoin` "results in `git log` showing an extra copy of every new commit that was created (the original, and the synthetic one)."

INFERRED: that `git subtree` may be missing from a given Windows git install. The evidence is structural — it sits under `contrib/` and has no page on git-scm.com — but no primary source fetched states whether it ships with Git for Windows. MEASURED, narrowly: this machine has `git 2.55.0.windows.3`; whether `git subtree` is present here was not tested.

### Cost

**Setup:** one command per consumer, plus section 0. **Upkeep:** low for one-way consumption, awkward for two-way. Each toolkit change is copied into each consumer as real commits, so the two copies drift until somebody runs `pull`, and a change made in a consumer needs a `split`/`push` round-trip with matching annotations. It is effectively **vendoring with a supported update path** — which makes it #31's "vendored into each consumer" candidate with the copying automated. Working on one repo alone is entirely fine; the files are simply there.

## 6. A wheel on disk

### The commands

DOCUMENTED: `uv build` — "uv build will build the project in the current directory, and place the built artifacts in a `dist/` subdirectory" ([build](https://docs.astral.sh/uv/concepts/projects/build/)); or `python -m build`, which "should generate two files in the `dist` directory" ([packaging tutorial](https://packaging.python.org/en/latest/tutorials/packaging-projects/)). DOCUMENTED: `--find-links` — "If a local path or `file://` URL that's a directory, then look for archives in the directory listing," and `--no-index` — "Ignore package index (only looking at `--find-links` URLs instead)" ([pip install](https://pip.pypa.io/en/stable/cli/pip_install/)). uv's equivalents are the `find-links` setting ("Locations to search for candidate distributions, in addition to those found in the registry indexes... the target must be a directory that contains packages as wheel files (.whl) or source distributions... at the top level", [settings](https://docs.astral.sh/uv/reference/settings/)) and `UV_FIND_LINKS` ([environment](https://docs.astral.sh/uv/reference/environment/)).

MEASURED: `uv build --wheel toolkit --out-dir dist` then `uv pip install --find-links=dist pascal-re-toolkit` works, and a **relative** `--find-links` resolves against the current directory.

### Two traps, measured

MEASURED: **`--no-index` breaks it.** Fully offline is not "install one wheel", it is "vendor the entire transitive closure":

    uv pip install --no-index --find-links=dist pascal-re-toolkit
    Because pyyaml was not found in the provided package locations and
    pascal-re-toolkit==0.1.0 depends on pyyaml>=6.0, ... unsatisfiable

MEASURED: **a rebuilt wheel at the same version is silently ignored.** After editing a source file and rebuilding, reinstalling reports `Checked 1 package` and installs nothing — the stale code stays. `--reinstall-package pascal-re-toolkit` fixes it, verified by the edit appearing in `site-packages`. This is the staleness trap in its purest form: no error, no warning, just an old copy. DOCUMENTED and closely related, from uv's [cache page](https://docs.astral.sh/uv/concepts/cache/): "uv caches based on the last-modified time of the source archive," and for a directory dependency uv "will only rebuild and reinstall local directory dependencies... if the `pyproject.toml`, `setup.py`, or `setup.cfg` file in the directory root has changed, or if a `src` directory is added or removed" — so editing only a `.py` file does not invalidate the cache. `--refresh`, `--refresh-package <name>` and `--reinstall` are the documented overrides, and `tool.uv.cache-keys` can widen the invalidation trigger.

### The absolute-path question

DOCUMENTED: uv shows both relative and absolute wheel paths as valid in `tool.uv.sources` — `uv add ./foo-0.1.0-py3-none-any.whl` and `uv add /example/foo-0.1.0-py3-none-any.whl`, the latter written back verbatim ([dependencies](https://docs.astral.sh/uv/concepts/projects/dependencies/)). DOCUMENTED gap: no fetched page discusses version-control portability of such a path, or warns that an absolute one is machine-specific.

**It can keep machine paths out of committed files, but only by keeping the location out of the repo entirely** — on the command line, or in `UV_FIND_LINKS`, or in user-level config. DOCUMENTED, uv's config discovery: project `pyproject.toml`/`uv.toml`, then user `%APPDATA%/uv/uv.toml` on Windows, then system `%PROGRAMDATA%/uv/uv.toml` ([configuration files](https://docs.astral.sh/uv/concepts/configuration-files/)). DOCUMENTED, pip's Windows locations: user `%APPDATA%/pip/pip.ini`, global `C:/ProgramData/pip/pip.ini`, site `%VIRTUAL_ENV%/pip.ini` ([configuration](https://pip.pypa.io/en/stable/topics/configuration/)). A committed `--find-links` pointing into a sibling checkout is a relative-layout assumption, exactly as in option 2.

### Cost

**Setup:** section 0, plus a build step. **Upkeep:** the worst of the lot for a package under active development. Every toolkit change needs a rebuild, and then either a version bump or a forced reinstall in each consumer, or the consumer keeps running old code with no indication. Working on one repo alone is fine once installed — the wheel's contents are copied in, not linked.

## 7. A private index

### A directory as a PEP 503 index

DOCUMENTED: [PEP 503](https://peps.python.org/pep-0503/) requires a root page linking normalised project names and a per-project page linking files, all URLs ending in `/`, with normalisation `re.sub(r"[-_.]+", "-", name).lower()`. DOCUMENTED: packaging.python.org's [hosting your own index](https://packaging.python.org/en/latest/guides/hosting-your-own-index/) says "within a root directory you need to create a directory for each project. This directory should be the normalized name of the project," served by any static file server with autoindex. DOCUMENTED: [PEP 691](https://peps.python.org/pep-0691/) adds a JSON serialisation but "does not introduce new features into the API" — HTML per PEP 503 remains sufficient.

DOCUMENTED: pip's `--index-url` "should point to a repository compliant with PEP 503... or a local directory laid out in the same format," and pip documents `file://` explicitly for `--find-links`. uv documents a local directory index as a bare path with `format = "flat"` rather than a `file://` URL. DOCUMENTED gaps: no fetched page shows a `file://` example for uv's `--index-url`, and **no primary source documents Windows drive-letter handling in `file://` index URLs** — the only material found was open pip issue [#10115](https://github.com/pypa/pip/issues/10115), which is a bug report, not documentation. Given that `git+file://` with a drive letter panics uv outright (section 3, MEASURED), this undocumented corner deserves suspicion rather than trust.

### A server

DOCUMENTED, [pypiserver](https://pypi.org/project/pypiserver/): the minimum is `pypi-server run -p 8080 ~/packages`. Packages arrive by `twine`, `pip`, setuptools, or "simply copied with scp". It is unauthenticated by default — "We strongly advise to password-protect your uploads!" — with `-P htpasswd.txt` adding auth, and by default only `update` actions require it, so downloads and listing stay open.

DOCUMENTED, [devpi](https://devpi.net/docs/devpi/devpi/stable/+doc/quickstart-server.html): `devpi-init`, `devpi-server --port 4040 --serverdir <dir>`, then `devpi use`, `devpi login root --password ''`, create a user, `devpi index -c dev bases=root/pypi`. "When started afresh, devpi-server will not contain any users or indexes except for the root user," whose password is empty. `devpi use --set-cfg <index>` writes the consumer's local pip/uv config for you.

### Consumer configuration and credentials

DOCUMENTED: `UV_INDEX_URL` is "Equivalent to the `--index-url` command-line argument. (Deprecated: use `UV_DEFAULT_INDEX` instead.)", alongside `UV_DEFAULT_INDEX` and `UV_INDEX` ([environment](https://docs.astral.sh/uv/reference/environment/)); `[[tool.uv.index]]` is the file equivalent, with `explicit = true` restricting an index to sources that name it. DOCUMENTED: credentials may be embedded in the index URL or supplied as `UV_INDEX_<NAME>_USERNAME` / `UV_INDEX_<NAME>_PASSWORD`; "uv supports discovery of credentials from netrc and keyring," keyring requiring `--keyring-provider subprocess`; and uv will not persist index credentials into `pyproject.toml` or `uv.lock` because those are often committed ([indexes](https://docs.astral.sh/uv/concepts/indexes/)).

### The absolute-path question

**A server keeps every machine path out of every committed file cleanly** — the consumers need only a URL such as `http://localhost:4040/...`, which is not a filesystem path at all, and it can live in user-level config or an environment variable rather than in the repo. A **directory** index is the same as option 6: a path, therefore either relative-layout or uncommitted.

### Is it worth it at this scale?

That is #31's call, but the facts that bear on it: it is the only option requiring a **running process** on a single developer's machine, it inherits every staleness problem of option 6 (an index serves built artifacts, so a change means rebuild, upload, reinstall), and its distinctive benefits — multi-consumer distribution, version pinning, mirroring, replication, auth — address problems this project does not currently have with two consumers, one developer, and no CI. DOCUMENTED for contrast, packaging.python.org's own comparison: pypiserver offers "package upload, no PyPI fall-through"; devpi offers "multiple indexes with inheritance, with syncing, replication, fail-over; mirroring".

## 8. Summary table

Read this as a cost sheet, not a ranking. "Machine path out of committed files" is the binding constraint from #31.

| option | setup cost | upkeep cost | machine path out of committed files? | survives the other repo not being checked out? |
|---|---|---|---|---|
| **1. editable install from a path** | prereq + one command per venv | near zero; edits are live | **yes** — everything absolute lands in git-ignored `.venv` (MEASURED) | yes, but imports fail with a bare `ModuleNotFoundError` (MEASURED) |
| **2. `[tool.uv.sources]` path / workspace** | prereq + a few committed lines | zero while the layout holds | **yes if relative** — `uv.lock` keeps `../tk` verbatim (MEASURED); no if absolute. Commits a relative-layout assumption either way | **no** — `uv lock` and `uv sync` both fail hard, and an optional dependency group does not help (MEASURED) |
| **3. git dependency** | prereq + one line + credential helper (already present) | push, then bump-and-relock in each consumer; no editable liveness | **yes** for a remote URL, and uv refuses to persist credentials (DOCUMENTED). No for `git+file://`, which also panics uv unless the drive colon is percent-encoded (MEASURED) | **yes** — resolves from the remote |
| **4. git submodule** | prereq + `git submodule add` per consumer | highest; detached HEAD, gitlink bumps, `git pull` not updating contents | **yes** for a normal or relative URL; a `file://D:/...` URL is committed verbatim into `.gitmodules` (DOCUMENTED) | yes — it is a real checkout inside the consumer |
| **5. git subtree** | prereq + one command per consumer | low one-way, awkward two-way (`split`/`push`, matching annotations) | **yes, unconditionally** — the URL is never recorded in any tracked file (DOCUMENTED) | yes — the files are simply present |
| **6. wheel on disk** | prereq + a build step | worst; rebuild and force-reinstall per consumer, or run stale code silently | only by keeping the location out of the repo (`UV_FIND_LINKS`, CLI, or `%APPDATA%/uv/uv.toml`) | yes once installed |
| **7. private index** | highest; a process to run and keep running | as option 6, plus an upload step | **yes** — a URL, not a path | yes once installed |

## 9. What the documentation does not answer

Kept explicitly, because the next session should not mistake these for settled. Where this session closed a gap by measuring, that is noted — a single measurement on one machine and one uv version, not a documented guarantee.

- **CLOSED BY MEASUREMENT** — whether `uv.lock` stores absolute or relative paths for a path source (relative, verbatim); what `uv lock`/`uv sync` do when a path source is missing (hard failure, including for excluded dependency groups); whether a uv workspace member may live outside the workspace root (it may).
- Whether uv shells out to system `git` and therefore inherits Windows Git Credential Manager, or speaks the protocol itself. Not stated either way.
- Whether an **editable git dependency** is supported by uv. Documented for `path` and workspace sources only; no `git =` example combines with `editable = true`. Absence of a stated feature, not a prohibition.
- `--no-cache` semantics specific to git refs, e.g. forcing a branch re-fetch.
- Whether `git subtree` ships with Git for Windows. Inferred as uncertain from its `contrib/` location and the 404 on git-scm.com; untested on this machine.
- Windows drive-letter handling in `file://` index and find-links URLs. No primary source; only open pip issue [#10115](https://github.com/pypa/pip/issues/10115). The measured uv panic on `git+file:///C:/...` suggests this corner is genuinely rough.
- Whether rebuilding a wheel with an identical filename is ever picked up automatically. MEASURED as "no" for one case; the documented cache key is the archive's last-modified time, and the docs do not say what happens when mtime granularity collides.
- pip's own wheel-cache invalidation rules. Not found in the pages fetched; only uv's cache page documents cache keys in detail.
- No git document addresses Python import mechanics at all. That **both** git options still need a separate install or `sys.path` step on top is an inference from packaging, not something the git docs assert or deny — but it is what makes section 0 a prerequisite for every option here.
