# Project N<sub>2</sub>

_The final solution of dot-file management for Unix systems_

Project N<sub>2</sub> aims to solve all the pain points in general dot-file management,
such as version control, modularization, etc. It also provides an informative
and customizable `bash`/`tmux` UI.

## Install

    cd "$HOME"
    git clone git@github.com:hengyang-zhao/n2.git .n2
    .n2/install.sh

The installation is intentionally minimal. It appends entrance blocks to your
existing dot-files. It does not soft-link, backup, or overwrite your original
files.

You can also install N<sub>2</sub> to a playground outside of your `HOME`:

    PLAYGROUND=yes .n2/install.sh

or (to save some confirmation prompts)

    AUTO_CONFIRM=yes PLAYGROUND=yes .n2/install.sh

> [!NOTE]
> `AUTO_CONFIRM=yes` works in the regular (non-playground) mode too.

> [!NOTE]
> The cloned directory can be named and placed arbitrarily. It doesn't
> have to be named `.n2` or placed directly under your `HOME`. M<sub>2</sub>
> directories are discovered under `HOME` by default (see below), but
> additional directories anywhere on the filesystem can be added via
> `N2_EXTRA_M2_DIRS`.

## Uninstall

    .n2/uninstall.sh

This lists the files modified during installation. Remove the
`=== N2 ENTRANCE BEGIN ===` / `=== N2 ENTRANCE END ===` blocks from each
file manually.

## Features

### Comes with a manual

After installation, run `man n2` or `man m2` to pull up the reference
manuals.

### M<sub>2</sub> discovery

You must already have some configs in your dot-files. Move them into M<sub>2</sub>
directory(s) so they can be easily version-controlled.

> [!NOTE]
> You still have the freedom to keep your configs in their
> original places, i.e., `~/.bashrc`, `~/.vimrc`, etc. You can skip this section
> if you wish to do so.

An M<sub>2</sub> directory is a directory under your `HOME` named like `.m2*`. When
bash is initializing, N<sub>2</sub> will enumerate all the M<sub>2</sub> directories and source the
configurations under them. A typical M<sub>2</sub> directory looks like this:

    ~/.m2
    ├── bash
    │   ├── profile.d
    │   │   ├── 10-my-profile.sh
    │   │   ├── 20-another-profile.sh
    │   │   └── not-starting-with-number-is-ok.sh
    │   └── rc.d
    │       ├── 10-my-rc.sh
    │       ├── 50-another-rc.sh
    │       └── not-starting-with-number-is-ok.sh
    ├── exec
    │   ├── my-exec
    │   └── another-exec
    ├── git
    │   └── config
    ├── tmux
    │   └── conf
    └── vim
        ├── 10-my-config.vim
        ├── 20-another-config.vim
        └── not-starting-with-number-is-ok.vim

Then you know where to put your old configs.

If you don't like creating an M<sub>2</sub> directory from scratch, N<sub>2</sub> can automatically
create one:

    n2 create-m2

The demo M<sub>2</sub> dir is a good starting point. It already has several files to help
you customize N<sub>2</sub> and add personal configs.

> [!TIP]
> Version-controlling your M<sub>2</sub> dir is often a good idea.

You also have the freedom to have multiple M<sub>2</sub> directories. This becomes useful
when you want to separate your M<sub>2</sub> dirs for personal use and work. If this is
the case, a typical home directory will look like this:

    ~
    ├── .n2
    ├── .m2-10-personal
    ├── .m2-20-work
    └── MyOtherStuff

> [!NOTE]
> The M<sub>2</sub> directories are discovered in lexical order. Those odd-looking
> infixes `-10-` and `-20-` are just to control that order.

If you need M<sub>2</sub> directories outside of your `HOME`, set the
`N2_EXTRA_M2_DIRS` environment variable to a comma-separated list of absolute
paths:

    export N2_EXTRA_M2_DIRS=/opt/shared-m2,/srv/team-m2

These directories are loaded after the auto-discovered `~/.m2*` ones, so they
take highest priority. Non-existent paths are silently ignored.

For more details, see `man n2` and `man m2`.

### Customizable bash PS1

By default, N<sub>2</sub> has a rich bash [PS1](https://www.gnu.org/software/bash/manual/html_node/Controlling-the-Prompt.html#Controlling-the-Prompt)
prompt. In addition to a colorful `user@host` and current working directory, it
also has

- a git repo/branch indicator;
- the permission bits of the current directory if it's not readable or writable;
- the nesting level of the current bash, if it's not the outermost one;
- number of processes running in the background;
- the physical cwd, if the apparent cwd is a symlink;

and some less frequent ones

- the nice value of current bash if it's not 0;
- a chroot indicator honoring `debian_chroot`;
- the session name if in a GNU screen session;
- `IFS` value if not default (`\x20\x09\x0a`).

To check the current prompt:

    echo "$PS1"

To customize this, just overwrite `PS1` in your M<sub>2</sub> configs.

### Informative tmux status bar

The status bar shows

- hostname and session name;
- the current TTY path if the session is multi-attached;
- window list;
- system load / number of cores;
- date and time.

### Command expansion

Command expansion is the lines starting with `[#] -> XXX`, for example

    me@laptop ~
    $ ls
    [1] -> /opt/homebrew/opt/coreutils/libexec/gnubin/ls --color=auto (MM/DD/YYYY HH:MM:SS)
    -- OUTPUT SKIPPED --

or

    me@laptop &1 ~
    $ grep pattern < file | wc
    [1] -> /usr/bin/grep --color=auto pattern < file (MM/DD/YYYY HH:MM:SS)
    [2] -> /opt/homebrew/opt/coreutils/libexec/gnubin/wc (MM/DD/YYYY HH:MM:SS)
    -- OUTPUT SKIPPED --

or

    me@laptop ~
    $ echo hello && echo world
    [1] -> builtin echo hello (MM/DD/YYYY HH:MM:SS)
    hello
    [2] -> builtin echo world (MM/DD/YYYY HH:MM:SS)
    world

Features include

- telling if the command was an external command (by expanding its true path),
  or if it's a shell builtin;
- timestamping the commands right before the command is executed;
- breaking up commands by pipe operators and logical operators;
- making sure that once an expansion is printed, the command is starting to
  execute --- this is especially useful when you copy-paste a command with a
  trailing line-break character into bash, but you just don't know if it's
  already executing or waiting for `ENTER`.

### Better status reporting

Automatically prints the status code and timestamp after a user command
completes. If it's a piped command, it prints the status code of each pipelet.
The timestamp can be used together with the ones in command expansion to
measure how long a command ran.
