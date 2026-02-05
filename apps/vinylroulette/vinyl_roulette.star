"""
Applet: Vinyl Roulette
Summary: Random vinyl from Discogs
Description: Display a random vinyl from your Discogs collection on your Tidbyt device!
Author: kaffolder7
Shows: Album art, Artist, Title, Track count, Total duration
"""

load("render.star", "render")
load("encoding/base64.star", "base64")
load("http.star", "http")
load("cache.star", "cache")
load("random.star", "random")
load("encoding/json.star", "json")
load("schema.star", "schema")
load("humanize.star", "humanize")

# Discogs API base URL
DISCOGS_API_BASE = "https://api.discogs.com"

# Cache keys and TTLs
COLLECTION_CACHE_KEY = "discogs_collection_%s"
RELEASE_CACHE_KEY = "discogs_release_%s"
COLLECTION_CACHE_TTL = 21600  # 6 hours (matches your refresh interval)
RELEASE_CACHE_TTL = 86400     # 24 hours (release data rarely changes)
FOLDERS_CACHE_KEY = "discogs_folders_%s"
FOLDERS_CACHE_TTL = 86400     # 24 hours (folder names rarely change)

# Tidbyt display dimensions
DISPLAY_WIDTH = 64
DISPLAY_HEIGHT = 32

def main(config):
    """Main entry point for the Tidbyt app."""

    # Get configuration values
    credentials = config.str("credentials", "")
    # folder_id = config.str("folder_id", "0")  # Default to "0" (All folders)
    folder_id = config.str("folder_id", "f_0")  # Default to "f_0" (All folders)

    # Parse combined credentials (format: "username:token")
    username = ""
    token = ""

    if credentials and ":" in credentials:
        parts = credentials.split(":", 1)  # Split on first colon only
        username = parts[0].strip()
        token = parts[1].strip() if len(parts) > 1 else ""

    # Validate required config
    if not username:
        return render_error("Set Discogs username in credentials (username:token)")

    if not token:
        return render_error("Set Discogs token in credentials (username:token)")

    # Fetch a random release from the collection (filtered by folder if specified)
    release_data = get_random_release(username, token, folder_id)

    if release_data == None:
        return render_error("Could not fetch collection")

    if "error" in release_data:
        return render_error(release_data["error"])

    # Render the display
    return render_vinyl(config, release_data)


def get_random_release(username, token, folder_id = "f_0"):
    """
    Fetches a random *vinyl* release from the user's Discogs collection.
    Uses caching to minimize API calls.

    Args:
        username: Discogs username
        token: Discogs API token
        folder_id: Folder ID to filter by (prefixed with "f_", e.g., "f_0" = all folders)
    """

    # Build headers for Discogs API
    headers = {
        "User-Agent": "TidbytRandomVinyl/1.0",
        "Authorization": "Discogs token=" + token,
    }

    # Folder name lookup (folder_id -> name)
    folder_map = get_folder_map(username, headers)


    # # Strip the "f_" prefix if present (added to prevent scientific notation)
    # if folder_id and folder_id.startswith("f_"):
    #     folder_id = folder_id[2:]

    # # Normalize folder_id - default to "0" (all folders) if empty, invalid, or non-numeric
    # if not folder_id or folder_id == "" or folder_id == "None":
    #     folder_id = "0"

    # # Ensure folder_id is a valid numeric string
    # folder_id = folder_id.strip()
    # is_numeric = True
    # for char in folder_id:
    #     if char not in "0123456789":
    #         is_numeric = False
    #         break

    # if not is_numeric or folder_id == "":
    #     folder_id = "0"


    # Normalize folder_id (schema dropdown returns strings like "f_0").
    # Always coerce to string, strip whitespace, then strip the "f_" prefix if present.
    folder_id = "%s" % folder_id
    folder_id = folder_id.strip()

    if folder_id.startswith("f_"):
        folder_id = folder_id[2:]

    # Default to "0" (all folders) if empty or placeholder
    if folder_id == "" or folder_id == "None":
        folder_id = "0"

    # Check cache for collection metadata (include folder_id in cache key)
    cache_key = (COLLECTION_CACHE_KEY % username) + "_folder_%s" % folder_id
    cached_collection = cache.get(cache_key)

    collection_info = None
    if cached_collection:
        collection_info = json.decode(cached_collection)
    else:
        # Fetch first page to get total count for this folder
        collection_url = "%s/users/%s/collection/folders/%s/releases?per_page=1" % (
            DISCOGS_API_BASE,
            username,
            folder_id,
        )

        resp = http.get(collection_url, headers=headers)

        if resp.status_code != 200:
            # return {"error": "API error: %d" % resp.status_code}
            # Show folder_id in error to help debug
            return {"error": "API %d: folder %s" % (resp.status_code, folder_id)}

        data = resp.json()

        if "pagination" not in data:
            return {"error": "Invalid API response"}

        collection_info = {
            "total_items": data["pagination"]["items"],
            "per_page": 50,  # We'll use 50 per page for fetching
        }

        # Cache the collection info
        cache.set(cache_key, json.encode(collection_info), ttl_seconds=COLLECTION_CACHE_TTL)

    total_items = int(collection_info["total_items"])

    if total_items == 0:
        folder_name = folder_map.get(folder_id, "this folder")
        if folder_id == "0":
            return {"error": "Collection is empty"}
        else:
            return {"error": "No releases in %s" % folder_name}

    # Rejection sampling: keep picking random items until we hit a Vinyl entry.
    # (Discogs collection paging doesn't provide a server-side "format=Vinyl" filter.)
    MAX_RANDOM_ATTEMPTS = 25

    for _ in range(MAX_RANDOM_ATTEMPTS):
        random_index = random.number(0, total_items - 1)
        page = (random_index // 50) + 1
        item_on_page = random_index % 50

        # Fetch the page containing our random item (using the selected folder)
        page_url = "%s/users/%s/collection/folders/%s/releases?page=%d&per_page=50" % (
            DISCOGS_API_BASE,
            username,
            folder_id,
            page,
        )

        resp = http.get(page_url, headers=headers)
        if resp.status_code != 200:
            return {"error": "Failed to fetch page"}

        page_data = resp.json()
        releases = page_data.get("releases", [])
        if len(releases) == 0:
            return {"error": "No releases on page"}

        # Handle edge case where item_on_page might be out of bounds
        if item_on_page >= len(releases):
            item_on_page = len(releases) - 1

        collection_item = releases[item_on_page]
        basic_info = collection_item.get("basic_information", {})

        formats = basic_info.get("formats", [])
        if not is_vinyl(formats):
            continue

        release_id = int(basic_info.get("id", 0))
        if release_id == 0:
            continue

        # Get detailed release info (for duration/track count)
        release_details = get_release_details(release_id, headers)

        item_folder_id = int(collection_item.get("folder_id", 0))
        folder_name = folder_map.get(str(item_folder_id), "")

        # Combine basic info with details
        return {
            "title": basic_info.get("title", "Unknown"),
            "artist": get_artist_name(basic_info.get("artists", [])),
            "thumb": basic_info.get("thumb", ""),
            "year": basic_info.get("year", 0),
            "format": get_format(formats),
            "tracks": release_details.get("tracks", 0),
            "duration": release_details.get("duration", ""),
            "duration_seconds": release_details.get("duration_seconds", 0),
            "folder_id": item_folder_id,
            "folder": folder_name,
        }

    # Provide a more helpful error message based on folder selection
    if folder_id == "0":
        return {"error": "Could not find a Vinyl release in your collection."}
    else:
        folder_name = folder_map.get(folder_id, "this folder")
        return {"error": "No Vinyl found in %s" % folder_name}


def get_release_details(release_id, headers):
    """
    Fetches detailed release information including tracklist.
    Returns track count and total duration.
    """

    if release_id == 0:
        return {"tracks": 0, "duration": "", "duration_seconds": 0}

    # Check cache first
    cache_key = RELEASE_CACHE_KEY % str(release_id)
    cached_release = cache.get(cache_key)

    if cached_release:
        return json.decode(cached_release)

    # Fetch release details
    release_url = "%s/releases/%d" % (DISCOGS_API_BASE, release_id)
    resp = http.get(release_url, headers=headers)

    if resp.status_code != 200:
        return {"tracks": 0, "duration": "", "duration_seconds": 0}

    data = resp.json()
    tracklist = data.get("tracklist", [])

    # Count actual tracks (exclude headings, index tracks, etc.)
    track_count = 0
    total_seconds = 0

    for track in tracklist:
        track_type = track.get("type_", "track")
        if track_type == "track":
            track_count += 1
            duration_str = track.get("duration", "")
            if duration_str:
                total_seconds += parse_duration(duration_str)

    # Format total duration
    duration_formatted = format_duration(total_seconds)

    result = {
        "tracks": track_count,
        "duration": duration_formatted,
        "duration_seconds": total_seconds,
    }

    # Cache the result
    cache.set(cache_key, json.encode(result), ttl_seconds=RELEASE_CACHE_TTL)

    return result


def parse_duration(duration_str):
    """Parses a duration string like '3:45' or '1:23:45' into seconds."""

    if not duration_str:
        return 0

    parts = duration_str.split(":")

    if len(parts) == 2:
        # MM:SS format
        minutes = int(parts[0]) if parts[0].isdigit() else 0
        seconds = int(parts[1]) if parts[1].isdigit() else 0
        return minutes * 60 + seconds
    elif len(parts) == 3:
        # HH:MM:SS format
        hours = int(parts[0]) if parts[0].isdigit() else 0
        minutes = int(parts[1]) if parts[1].isdigit() else 0
        seconds = int(parts[2]) if parts[2].isdigit() else 0
        return hours * 3600 + minutes * 60 + seconds

    return 0


def format_duration(total_seconds):
    """Formats seconds into a readable duration string."""

    if total_seconds == 0:
        return ""

    hours = total_seconds // 3600
    minutes = (total_seconds % 3600) // 60

    if hours > 0:
        return "%dh %dm" % (hours, minutes)
    else:
        return "%dm" % minutes


def get_artist_name(artists):
    """Extracts the primary artist name from the artists array."""

    if not artists or len(artists) == 0:
        return "Unknown Artist"

    # Join multiple artists with " & "
    names = []
    for artist in artists:
        name = artist.get("name", "")
        if name:
            # Remove trailing number disambiguation (e.g., "Artist (2)")
            if " (" in name and name.endswith(")"):
                name = name.rsplit(" (", 1)[0]
            names.append(name)

    if len(names) == 0:
        return "Unknown Artist"
    elif len(names) == 1:
        return names[0]
    elif len(names) == 2:
        return names[0] + " & " + names[1]
    else:
        return names[0] + " & others"


def is_vinyl(formats):
    # """True if any of the formats has name == 'Vinyl'."""
    # if not formats:
    #     return False
    # for f in formats:
    #     if (f.get("name", "") or "").lower() == "vinyl":
    #         return True
    """True if formats contains an object with name == 'Vinyl'."""
    for f in formats or []:
        if (f.get("name", "") or "").strip().lower() == "vinyl":
            return True
    return False


def get_folder_map(username, headers):
    """
    Returns a dict mapping folder_id (as a string) -> folder name.
    Cached to avoid extra API calls.
    """
    cache_key = FOLDERS_CACHE_KEY % username
    cached = cache.get(cache_key)
    if cached:
        return json.decode(cached)

    url = "%s/users/%s/collection/folders" % (DISCOGS_API_BASE, username)
    resp = http.get(url, headers=headers)
    if resp.status_code != 200:
        # Non-fatal: we'll just omit folder names.
        return {}

    data = resp.json()
    folders = data.get("folders", [])
    folder_map = {}
    for f in folders:
        fid = int(f.get("id", -1))
        if fid >= 0:
            folder_map[str(fid)] = f.get("name", "")

    cache.set(cache_key, json.encode(folder_map), ttl_seconds=FOLDERS_CACHE_TTL)
    return folder_map


def get_format(formats):
    """Extracts the primary format (e.g., 'LP', '12\"', 'CD')."""

    if not formats or len(formats) == 0:
        return ""

    return formats[0].get("name", "")


def hold(frame, n):
    # Repeat `frame` n times (at least once)
    if n < 1:
        n = 1
    return [frame] * n


def render_vinyl(config, release_data):
    """Renders the release information for the Tidbyt display."""

    title = release_data["title"]
    artist = release_data["artist"]
    thumb_url = release_data["thumb"]
    year = release_data["year"]
    tracks = release_data["tracks"]
    duration = release_data["duration"]
    folder = release_data.get("folder", "")

    # Build info line (folder + year + tracks + duration)
    info_parts = []

    # if folder:
    #     # Prefix helps distinguish from year/duration
    #     # info_parts.append("Folder: %s" % folder)
    #     # info_parts.append("%s" % folder)
    #     info_parts.append(folder)

    if year:
        info_parts.append(str(int(year)))

    # if tracks > 0:
    #     info_parts.append("%d tracks" % tracks)
    if tracks >= 0:
        label = "track" if tracks == 1 else "tracks"
        info_parts.append("%d %s" % (tracks, label))

    if duration:
        info_parts.append(duration)

    # info_line = " · ".join(info_parts) if info_parts else ""

    # Fetch album art if available
    album_art = None
    if thumb_url:
        art_resp = http.get(thumb_url)
        if art_resp.status_code == 200:
            album_art = art_resp.body()

    root_delay_ms = 50          # fast for marquees
    hold_ms = 3000              # 3 seconds per text
    n = hold_ms // root_delay_ms
    stats_color = config.str("album_stats_color", "#888888")

    children = []

    # # Discogs logo
    # discogs_logo = render.Image(
    #     src = ICON,
    #     width = 32,
    # )
    # children += hold(discogs_logo, n)
    # discogs_text = render.Text(content="Discogs", font="tom-thumb", color="#888888")
    # children += hold(discogs_text, n)

    # # Folder (always show)
    # folder_name = render.Marquee(
    #     width = 32,
    #     child = render.Text(
    #         content = info_parts[0],
    #         font = "tom-thumb",
    #         color = "#888888",
    #     ),
    # )
    # children += hold(folder_name, n)

    # Year (always show if present)
    if len(info_parts) > 0 and info_parts[0]:
        text0 = render.Text(content=info_parts[0], font="tom-thumb", color=stats_color)
        children += hold(text0, n)

    # Number of tracks (only include if it exists and is non-empty)
    if len(info_parts) > 1 and info_parts[1]:
        text1 = render.Text(content=info_parts[1], font="tom-thumb", color=stats_color)
        children += hold(text1, n)

    # Album duration (only include if it exists and is non-empty)
    if len(info_parts) > 2 and info_parts[2]:
        text2 = render.Text(content=info_parts[2], font="tom-thumb", color=stats_color)
        children += hold(text2, n)

    # Fallback: ensure at least one frame
    if len(children) == 0:
        # children = [render.Box()]
        children = [render.Text(content="", font="tom-thumb", color=stats_color)]

    info_cycler = render.Animation(children=children)

    # Build the display layout
    if album_art:
        # Layout with album art on the left
        return render.Root(
            delay = root_delay_ms,
            child = render.Row(
                expanded = True,
                main_align = "start",
                cross_align = "center",
                children = [
                    # Album art (scaled to fit height)
                    render.Image(
                        src = album_art,
                        width = 28,
                        height = 28,
                    ),
                    render.Box(width = 2, height = 1),  # Spacer
                    # Text info
                    render.Column(
                        expanded = True,
                        main_align = "center",
                        cross_align = "start",
                        children = [
                            # Discogs logo
                            # render.Image(
                            #     src = ICON,
                            #     width = 30,
                            #     # height = 14,
                            # ),
                            # Album name
                            render.Marquee(
                                width = 32,
                                child = render.Text(
                                    content = title,
                                    font = "tb-8",
                                    # font = "6x13",
                                    color = config.str("album_title_color", "#FFFFFF"),
                                ),
                            ),
                            render.Box(width = 0, height = 1),  # Spacer
                            # Artist name
                            render.Marquee(
                                width = 32,
                                child = render.Text(
                                    content = artist,
                                    font = "tom-thumb",
                                    color = config.str("album_artist_color", "#AAAAAA")
                                ),
                            ),
                            # render.Box(width = 0, height = 4),  # Spacer
                            render.Box(width = 0, height = 3),  # Spacer
                            # # Number of tracks
                            # render.Text(
                            #     content = info_line,
                            #     font = "tom-thumb",
                            #     color = "#888888",
                            # ) if info_line else render.Box(height = 1),
                            # render.Marquee(
                            #     width = 32,
                            #     child = render.Text(
                            #         content = info_line,
                            #         font = "tom-thumb",
                            #         color = "#AAAAAA",
                            #     ),
                            # ),
                            info_cycler if len(info_parts) > 0 and config.bool("show_stats", True) else render.Box(height = 1),
                            # Folder name
                            render.Marquee(
                                width = 32,
                                child = render.Text(
                                    content = folder,
                                    font = "tom-thumb",
                                    # color = "#888888",
                                    color = config.str("folder_name_color", "#666666"),
                                ),
                            ),
                        ],
                    ),
                ],
            ),
        )
    else:
        # Text-only layout (no album art)
        return render.Root(
            child = render.Box(
                padding = 1,
                child = render.Column(
                    expanded = True,
                    main_align = "center",
                    cross_align = "center",
                    children = [
                        # # Discogs logo
                        # render.Image(
                        #     src = ICON,
                        #     width = 32,
                        # ),
                        # Album name
                        render.Marquee(
                            width = 62,
                            child = render.Text(
                                content = title,
                                font = "6x13",
                                color = config.str("album_title_color", "#FFFFFF"),
                            ),
                        ),
                        render.Box(width = 0, height = 1),  # Spacer
                        # Artist name
                        render.Marquee(
                            width = 62,
                            child = render.Text(
                                content = artist,
                                font = "tom-thumb",
                                color = config.str("album_artist_color", "#AAAAAA")
                            ),
                        ),
                        # render.Box(width = 0, height = 4),  # Spacer
                        render.Box(width = 0, height = 3),  # Spacer
                        # # Number of tracks
                        # render.Text(
                        #     content = info_line,
                        #     font = "tom-thumb",
                        #     color = "#888888",
                        # ) if info_line else render.Box(height = 1),
                        # render.Marquee(
                        #     width = 32,
                        #     child = render.Text(
                        #         content = info_line,
                        #         font = "tom-thumb",
                        #         color = "#AAAAAA",
                        #     ),
                        # ),
                        info_cycler if len(info_parts) > 0 and config.bool("show_stats", True) else render.Box(height = 1),
                        # Folder name
                        # render.Marquee(
                        #     width = 32,
                        #     child = render.Text(
                        #         content = folder,
                        #         font = "tom-thumb",
                        #         # color = "#888888",
                        #         color = config.str("folder_name_color", "#666666"),
                        #     ),
                        # ),
                    ],
                ),
            ),
        )


def render_error(message):
    """Renders an error message on the display."""

    return render.Root(
        child = render.Box(
            padding = 2,
            child = render.WrappedText(
                content = message,
                font = "tom-thumb",
                color = "#FF6666",
                align = "center",
            ),
        ),
    )


def folder_dropdown_handler(credentials):
    """
    Handler for schema.Generated that fetches folders from Discogs.
    Receives the credentials field value in format "username:token".
    Returns a list containing a Dropdown populated with user's collection folders.
    """
    # Parse the combined credentials (format: "username:token")
    username = ""
    token = ""

    if credentials and ":" in credentials:
        parts = credentials.split(":", 1)  # Split on first colon only (token might contain colons)
        username = parts[0].strip()
        token = parts[1].strip() if len(parts) > 1 else ""

    if not username or not token:
        # Return a placeholder dropdown until credentials are provided
        return [
            schema.Dropdown(
                id = "folder_id",
                name = "Collection Folder",
                desc = "Enter credentials above as username:token",
                icon = "folder",
                # default = "0",
                default = "f_0",
                options = [
                    # schema.Option(display = "All Folders", value = "0"),
                    schema.Option(display = "All Folders", value = "f_0"),
                ],
            ),
        ]

    headers = {
        "Authorization": "Discogs token=%s" % token,
        "User-Agent": "TidbytRandomVinyl/1.0",
    }

    url = "%s/users/%s/collection/folders" % (DISCOGS_API_BASE, username)
    resp = http.get(url, headers = headers)

    if resp.status_code != 200:
        # Return error placeholder if API call fails
        return [
            schema.Dropdown(
                id = "folder_id",
                name = "Collection Folder",
                desc = "Could not load folders (check credentials).",
                icon = "folder",
                # default = "0",
                default = "f_0",
                options = [
                    # schema.Option(display = "All Folders", value = "0"),
                    schema.Option(display = "All Folders", value = "f_0"),
                ],
            ),
        ]

    data = resp.json()
    folders = data.get("folders", [])

    # Build options list - "All" folder (id=0) is typically first in the API response
    # but let's ensure it's always there as the default option
    options = []
    has_all_folder = False

    for f in folders:
        folder_id = f.get("id")
        folder_name = f.get("name", "Unknown")

        if folder_id == None:
            continue

        # Check if this is the "All" folder (id=0)
        if folder_id == 0:
            has_all_folder = True
            # Put "All Folders" first with a clearer name
            options.insert(0, schema.Option(
                display = "All Folders (%s)" % folder_name,
                # value = "0",
                value = "f_0",
            ))
        else:
            # Prefix with "f_" to prevent scientific notation conversion
            options.append(schema.Option(
                display = folder_name,
                # value = str(folder_id),
                value = "f_%d" % int(folder_id),
            ))

    # Ensure we always have an "All Folders" option
    if not has_all_folder:
        # options.insert(0, schema.Option(display = "All Folders", value = "0"))
        options.insert(0, schema.Option(display = "All Folders", value = "f_0"))

    return [
        schema.Dropdown(
            id = "folder_id",
            name = "Collection Folder",
            desc = "Filter random vinyl selection by folder.",
            icon = "folder",
            # default = "0",
            default = "f_0",
            options = options,
        ),
    ]


def stats_options_handler(show_stats):
    """
    Handler called when show_stats changes.
    Returns sub-toggles only when show_stats is "true".
    """
    if show_stats == "true":
        return [
            schema.Toggle(
                id = "show_year",
                name = "Show Year",
                desc = "Display album year (only when Show Stats is enabled).",
                icon = "calendar",
                default = True,
            ),
            schema.Toggle(
                id = "show_tracks",
                name = "Show Tracks",
                desc = "Display album tracks (only when Show Stats is enabled).",
                icon = "list",
                default = True,
            ),
            schema.Toggle(
                id = "show_duration",
                name = "Show Duration",
                desc = "Display album duration (only when Show Stats is enabled).",
                icon = "clock",
                default = True,
            ),
            schema.Color(
                id = "album_stats_color",
                name = "Album Stats Color",
                desc = "The text color of the album's stats. (e.g. what cycles through)",
                icon = "brush",
                default = "#888888",
            ),
        ]
    else:
        return []  # Hide these fields when stats are disabled


def get_schema():
    """
    Defines the configuration schema for the Tidbyt mobile app.
    Users will enter their Discogs username and personal access token.
    """

    return schema.Schema(
        version = "1",
        fields = [
            schema.Text(
                id = "credentials",
                name = "Discogs Credentials",
                desc = "Enter as username:token (get token from discogs.com/settings/developers)",
                icon = "key",
            ),
            schema.Generated(
                id = "folder_dropdown",
                source = "credentials",  # Now watches the single combined field
                handler = folder_dropdown_handler,
            ),
            schema.Color(
                id = "album_title_color",
                name = "Album Title Color",
                desc = "The text color of the album title.",
                icon = "brush",
                default = "#FFFFFF",
            ),
            schema.Color(
                id = "album_artist_color",
                name = "Album Artist Name Color",
                desc = "The text color of the album artist.",
                icon = "brush",
                default = "#AAAAAA",
            ),
            schema.Color(
                id = "folder_name_color",
                name = "Folder Name Color",
                desc = "The text color of the folder name.",
                icon = "brush",
                default = "#888888",
                palette = [
                    "#888888",
                    "#34495E",
                    "#666666",
                    "#8E44AD",
                ],
            ),
            schema.Toggle(
                id = "show_stats",
                name = "Show Stats",
                desc = "Display album stats (year, duration, etc.)",
                icon = "info",
                default = False,
            ),
            schema.Generated(
                id = "stats_options",
                source = "show_stats",      # Watch this field
                handler = stats_options_handler,  # Call this when it changes
            ),
        ],
    )
