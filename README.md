# Data of the Ong Music app

Files edited by hand and by a browser extension, read by the app from
`https://raw.githubusercontent.com/nbros/ong_music/data/`. The app downloads them with the sheets, keeps them, and
works without them: if a file is missing or does not read, nothing of it shows.

## `vods.tsv`: the full recordings (VODs) of the streams

One YouTube video per line, tab-separated, UTF-8, a header line first:

    date	part	id	seconds	posted	title

| column    | what it holds                                                                                        |
|-----------|------------------------------------------------------------------------------------------------------|
| `date`    | the date the stream **started in Sydney**, `YYYY-MM-DD`; `YYYY-MM-DD#2` for the second stream that started that day in Sydney (`#3`...), in the order of the Songs sheet. Empty when unknown: the line is ignored. |
| `part`    | `1` for the only video of a stream or the first of several, `2` for the second...                    |
| `id`      | the 11 characters of the YouTube id (`https://youtu.be/<id>`)                                         |
| `seconds` | the length of the video in whole seconds; empty when unknown                                          |
| `posted`  | the day the link was posted on Discord (information only)                                             |
| `title`   | the title of the video (information only)                                                             |

The app opens a song at its uptime: in part 1, or in part 2 at the uptime minus the length of part 1, and so on.
So the `seconds` of every part that is followed by another part must be filled, or the plays after it get no link.

Rules:
- the first line that is neither empty nor a comment must be the header (its first cells `date`, `part`, `id`): a
  file without it is not taken (the app keeps the copy it has), nor is a file larger than 2 MB;
- lines beginning with `#` and empty lines are ignored; so is a line whose date, part or id does not read;
- when two lines name the same stream and part, the **later one wins** (a re-upload);
- a stream's VOD is its parts 1, 2... without a hole: the parts after a missing one are ignored;
- the extension only **adds** lines at the end (for ids the file does not hold, even in a comment) and may fill an
  empty `seconds`. It never changes anything else: corrections by hand stay.

### Correcting a line by hand

Edit the file on GitHub (branch `data`) and fix the cell, keeping the tabs. Before giving a video a stream, check
that it can be that stream's recording: its `seconds` at least the stream's length (the largest uptime of its rows,
markers included, as `tool/vods_check.dart` prints it), give or take a few minutes. A wrong link is worse than none:
when two streams fit, or nothing tells, leave the date empty.
- wrong day: change `date` (the Sydney date of the start of the stream, as `tool/vods_check.dart` lists it);
- the second stream of a day: add `#2` to the date (`2022-05-08#2`);
- a video that is no stream's recording (a separate Concert Grand video, a non-music stream): empty its `date`, or
  put `# ` in front of the line;
- write a `# ...` line above it saying what you changed and why.

Never delete a line: the extension would add it again.

### Checking the file

From a checkout of the app, with the two sheets exported as CSV (or the copies of the branch `sheets-snapshot`):

    dart run tool/vods_check.dart highlights.csv songs.csv vods.tsv

It prints the streams with a VOD per year, the plays that get a link, the VODs that match no stream (with the
streams a day before and after, and their lengths), the days of several streams, the lines ignored and why, the
lines replaced by a later one, the parts whose missing length blocks links, and the streams longer than their VOD.

## `offsets.tsv`: where a song is in a recording that does not start with its stream

One line per correction, tab-separated, UTF-8, a header line first:

    date	uptime	offset	note

| column   | what it holds                                                                                          |
|----------|--------------------------------------------------------------------------------------------------------|
| `date`   | the stream, written as the `date` cell of `vods.tsv` (`2021-07-30`, `2022-05-08#2`)                     |
| `uptime` | empty: the whole stream; `1:00:00+`: the songs from that uptime on; `2:03:23`: the songs of exactly that uptime |
| `offset` | whole seconds added to the uptime to give the position in the VOD (all its parts end to end): `-1140` when the recording starts 19 minutes after the stream |
| `note`   | free text (information only)                                                                            |

A song takes the line of its exact uptime, else the last `+` line at or before its uptime (the whole-stream line
counting as `0:00:00+`), else no offset. A song the offset puts before the start of the recording gets no link. A
whole-stream line of `0` changes nothing: it records that the stream was checked.

Rules:
- the first line that is neither empty nor a comment must be the header (its first cells `date`, `uptime`,
  `offset`): a file without it is not taken (the app keeps the copy it has), nor is a file larger than 256 KB;
- lines beginning with `#` and empty lines are ignored; so is a line whose date, uptime or offset does not read (an
  offset beyond a day either way does not);
- when two lines have the same date and the same uptime cell, the **later one wins**;
- the tool of the extension rewrites the lines of one stream at a time and leaves every other line as it is.

Check it with `vods.tsv` (the fourth argument is optional):

    dart run tool/vods_check.dart highlights.csv songs.csv vods.tsv offsets.tsv

## `aliases.txt`: the names of one person

One group per line, the names separated by commas (case and accents do not matter); `#` comments and empty lines
are ignored. A name belongs to one group at most: a file that puts a name in two groups, holds no group or is larger
than 256 KB is not taken, and the app keeps the table it has. A change applies the next time the app reads the sheets.
