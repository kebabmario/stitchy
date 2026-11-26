# Extensions

Extensions are island tabs you build yourself, without code. Each one reads data
from web APIs or feeds, lays it out with Stitchy's components, and can raise alerts
when the data changes. Enabled extensions appear in the island's **Extensions** tab.

- [Quick start](#quick-start)
- [Data sources](#data-sources)
- [Paths and templates](#paths-and-templates)
- [Components](#components)
- [Lists](#lists)
- [Styling](#styling)
- [Automations](#automations)
- [Import and export](#import-and-export)
- [Refresh, caching and errors](#refresh-caching-and-errors)
- [Security model](#security-model)
- [File format](#file-format)
- [Limits](#limits)

## Quick start

1. Open **Settings › Extensions** and click **New Extension**. The editor opens.
2. In the inspector's **Data** tab, enter an address (for example
   `https://api.open-meteo.com/v1/forecast?latitude=52.5&longitude=13.4&current=temperature_2m`)
   and click **Test Connection** (⌘↩). The response's fields appear as a tree.
3. Select a component on the canvas and click **Bind** next to a field, or click
   **+** next to a field to add a suitable component for it.
4. Style it in the **Component** tab. The canvas is a live preview at island width.
5. Turn the extension on in the **Extension** tab. It now shows in the island.

Changes save automatically. Close the editor window when you're done.

## The editor

| Area | What it does |
|---|---|
| Components (left) | Click to add to the selected container, or drag onto the canvas |
| Layers (left) | The component tree. Drag rows to reorder or move them into containers; Delete removes the selection |
| Canvas (centre) | Live preview with the last fetched data. Click to select; "Preview only" turns selection off |
| Extension tab | Name, description, icon (built-in symbols, Stitchy's rocket, or your own image), enabled |
| Data tab | Address, query parameters, headers, authentication, refresh interval, more APIs, Test Connection, field tree |
| Component tab | Binding, kind-specific options, click link, text, appearance, move/duplicate/delete |
| ⚡ tab | Automations |

## Data sources

Every extension has one **first API** and up to 12 **more APIs**.

- **Method:** GET only. Extensions read data; they never send it.
- **Formats:** JSON, and XML feeds (RSS, Atom, other XML). See [Feeds](#feeds).
- **Addresses:** `https://` only; `http://` is allowed for `localhost`, `127.0.0.1`
  and `::1` so you can use local servers.
- **Query parameters and headers:** name/value pairs. The first API's query values
  may use `{@now}` (see [templates](#paths-and-templates)).
- **Authentication** (first API only): none, bearer token, API key in a header, or
  API key in the query. The token goes into your **Keychain**, never into the
  extension file, and is never sent to the extra APIs.
- **Refresh every:** 30 seconds to 24 hours (default 5 minutes).

### More APIs

Extra APIs are fetched after the first, in order. Each has a short name (letters,
digits, `_`), and you bind to its data with `$name`, e.g.
`$weather.hourly.cloud_cover[0]`.

Their query values, and their URL path, can use values from earlier responses:

```text
https://api.open-meteo.com/v1/forecast
  latitude   = {results[0].pad.latitude}
  longitude  = {results[0].pad.longitude}
  start_hour = {results[0].net|hour}

https://hacker-news.firebaseio.com/v0/item/{[0]}.json
https://api.github.com/repos/{$repos.items[0].owner.login}/{$repos.items[0].name}/releases
```

If a value it needs is missing, that API is skipped for this refresh and the tab
shows a small warning. A failing extra API never hides the others' data.

### Feeds

XML is turned into the same tree as JSON:

| XML | Becomes |
|---|---|
| `<title>Hello</title>` | `"title": "Hello"` |
| Attributes | `@name`, e.g. `link.@href`, `media:content.@url` |
| Repeated elements | Arrays, e.g. `rss.channel.item[0]` |
| Text next to child elements or attributes | `#text` (a component bound to the element shows it) |
| HTML text (descriptions, content) | Plain text, with the first image as `#image` |

Typical paths: RSS `rss.channel.item`, `title`, `link`, `pubDate`, `dc:creator`,
`category`; Atom `feed.entry`, `title`, `link.@href`, `published`, `author.name`.
RSS dates (`Wed, 25 Nov 2026 12:00:28 +0000`) and ISO dates both work.

## Paths and templates

**Paths** point into the data:

| Path | Meaning |
|---|---|
| `main.temp` | Key inside an object |
| `items[0].title` | First item of an array |
| `[0]` | First item when the response itself is an array |
| `$weather.hourly.time[0]` | Inside the extra API named `weather` |
| `pubDate ?? published ?? updated` | The first path that has a value |
| `@source` | Inside a merged list: the label of the list the item came from |

**Templates** insert values into text: `{value}` is the component's bound value,
so a text bound to `main.temp` with `{value}°` shows `21°`. In addresses, links and
alert titles, `{any.path}` inserts that field.

`{@now}` is the current time. Filters, all in UTC:

| Filter | Example result |
|---|---|
| `{@now\|date}` | `2026-11-26` |
| `{@now\|date-7}` | `2026-11-19` (7 days ago) |
| `{@now\|unix-2}` | Unix seconds, 2 days ago |
| `{results[0].net\|hour}` | `2026-11-27T08:00` |

## Components

| Component | Shows | Options |
|---|---|---|
| Text | Bound value or your text; `{value}` template | Line limit |
| Heading | Larger text | Same as text |
| Number | Bound number | Decimals, prefix, suffix |
| Date | Bound date (ISO, RSS, Unix seconds/ms) | Full, relative ("2 hr. ago"), date, time |
| Countdown | Time left until the bound date, live | |
| Progress Bar | Bound number ÷ maximum | Maximum, show the remainder |
| Progress Ring | Same, as a ring with a percentage | Maximum, show the remainder |
| Status | Coloured dot and label | Colour per value; ok/online/error/offline etc. coloured automatically |
| Image | Bound https image URL | Width, height, corner radius |
| Icon | An SF Symbol | Symbol name |
| Chart | Line chart of a list of numbers, or of one number field per item | Number field |
| List | Repeats its children for each item | See [Lists](#lists) |
| Button | Opens an https link | Link (`{value}` = bound value) |
| Divider | Thin line | Colour, thickness |
| Container | Groups children | Vertical, horizontal, grid (columns) |

Any component except buttons and dividers can also **open a link when clicked**
(Component › Click to open), e.g. a whole news row with `{link ?? url}`.

When a bound text, number, date, status or image has no value and no fallback text,
it hides itself instead of showing a placeholder; texts using `{value}` hide too.
A bound button with no value hides as well.

## Lists

Bind a list to an array; components inside it read from each item, so a text
inside a list bound to `title` shows each item's title.

- **Show up to:** how many items.
- **Merge several lists:** bind `Label = path, Label = path`, e.g.
  `Hacker News = $hn.hits, Ars Technica = $ars.rss.channel.item`. Each item gets
  its label as `@source`.
- **Newest first by:** a date path (use `??` when sources name it differently,
  e.g. `created_at ?? pubDate ?? published`).
- **Remove duplicates by:** a path compared ignoring case and punctuation, e.g. `title`.
- A single object (a feed with one entry) counts as a one-item list.
- **Empty text:** shown when there are no items.

## Styling

Every component has: font (standard, rounded, serif, monospaced), weight, size,
alignment, text colour, accent colour, background with opacity, padding, gap,
corner radius, border width and colour, fixed width/height, line limit and hidden.
Colours are names (`blue`, `green`…) or hex (`#0A84FF`).

## Automations

In the ⚡ tab: **WHEN** the data refreshes, **IF** all (or any) conditions match,
**THEN** show an island alert, or an alert plus a macOS notification.

- Conditions: is, is not, contains, is above, is below, is true, is false, exists,
  is missing, changes.
- Title and message can use `{path}` templates.
- An automation fires when its conditions *become* true, not on every refresh
  while they stay true, then waits its cooldown (1 minute to 24 hours).
- The first data after Stitchy launches only sets a starting point, so restarts
  don't repeat alerts.
- Up to 10 per extension. Automations can only notify you: they never open links,
  run anything or change settings.

## Import and export

**Settings › Extensions › ⋯ › Export…** saves a `.stitchyext` file;
**Import…** adds one.

Export never includes:
- the Keychain token or key;
- header or query values whose name looks secret (auth, token, key, secret,
  password, cookie, session, signature, credential, bearer);
- usernames or passwords written into addresses.

Your own icon image is included.

Import checks the file (1 MB, 500 components, format version), gives it new IDs,
and adds it **turned off with its automations off**, so nothing from a shared file
runs until you've looked at it. Add your own token if it needs one.

## Refresh, caching and errors

- Only **enabled** extensions with a data source contact their APIs.
- Each refresh fetches the first API, then the extra APIs in order.
- The last good response is cached in `~/Library/Caches/Stitchy/extensions/` and
  shown at launch; a fresh-enough cache delays the first request.
- Errors: the tab shows a warning badge with the reason and keeps the last data.
  Failed refreshes back off exponentially (up to 30 minutes). HTTP 429 waits for
  `Retry-After` (at least 5 minutes).
- Editing the address waits 1.5 s before fetching, so typing doesn't send a request
  per keystroke.
- **Refresh Now** is in the tab header and in Settings › Extensions › ⋯.

Respect the APIs' rate limits: an extension with 13 sources refreshing every
30 minutes makes 26 requests an hour.

## Security model

- Extensions are data. They can't run Swift, JavaScript, shell commands or
  AppleScript, and can't read local files.
- Requests: GET only, https only (http for localhost), 15 s timeout, 2 MB per
  response, ephemeral session with no cookies or shared cache. XML external
  entities are never resolved.
- Data from one API can only fill query values and single URL path segments of the
  next request (letters, digits, `-._~`). The scheme and host are always written
  by you, so data can't redirect requests elsewhere.
- Tokens live in the Keychain (service `app.stitchy.extensions`), go only to the
  first API, and never appear in the extension file, exports or logs.
- Links and images open or load only over https.
- Imported extensions start disabled.

## File format

Extensions are stored as JSON:
`~/Library/Application Support/Stitchy/extensions.json` holds
`{ "formatVersion": 2, "extensions": [ … ] }`; a `.stitchyext` file holds
`{ "stitchyExtensionPackage": 1, "exported": "…", "extension": { … } }`.

```jsonc
{
  "formatVersion": 2,
  "id": "UUID", "name": "Space Launches", "summary": "…",
  "icon": "stitchy.rocket", "iconImage": null,   // base64 PNG when you chose an image
  "enabled": true,
  "dataSource": {
    "url": "https://ll.thespacedevs.com/2.3.0/launches/upcoming/",
    "method": "GET",
    "query": [{ "id": "UUID", "key": "limit", "value": "8" }],
    "headers": [], "auth": "none", "authName": "X-API-Key", "refreshSeconds": 3600
  },
  "extraSources": [{ "id": "UUID", "name": "weather", "source": { /* same as dataSource */ } }],
  "root": {                                       // always a container
    "id": "UUID", "kind": "container", "axis": "vertical",
    "children": [{ "kind": "text", "binding": "results[0].name", "text": "{value}",
                   "style": { "fontSize": 15, "weight": "bold", "lineLimit": 2 } }]
  },
  "automations": [{ "name": "…", "enabled": true, "matchAll": true,
                    "conditions": [{ "path": "…", "op": "changes", "value": "" }],
                    "delivery": "island", "title": "{…}", "message": "", "cooldownMinutes": 30 }],
  "created": "2026-11-25T12:00:00Z", "modified": "2026-11-25T12:00:00Z"
}
```

Component fields: `kind` (`text`, `heading`, `image`, `icon`, `number`, `date`,
`countdown`, `progress`, `ring`, `status`, `list`, `chart`, `button`, `divider`,
`container`), `binding`, `text`, `symbol`, `style`, `children`, `axis`
(`vertical`, `horizontal`, `grid`), `columns`, `maxItems`, `decimals`, `prefix`,
`suffix`, `maximum`, `invert`, `statusColors`, `linkURL`, `sortBy`, `dedupeBy`,
`dateFormat` (`""`, `relative`, `date`, `time`). Every field except `kind` is
optional, so files from older versions keep loading. Version 1 files (no
automations or extra sources) load unchanged.

## Limits

| Limit | Value |
|---|---|
| Extra APIs per extension | 12 |
| Response size | 2 MB each |
| Request timeout | 15 s |
| Minimum refresh | 30 s |
| Automations per extension | 10 |
| Import file | 1 MB, 500 components |
| Icon image | 128×128 PNG, 200 KB |

Things extensions can't do: POST or other methods, run code, read files, compute
values (sums, differences), filter list items by a condition, or show in the
compact island.
