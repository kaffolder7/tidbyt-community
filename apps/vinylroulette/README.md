# Vinyl Roulette - Tidbyt App

Display a random vinyl from your Discogs collection on your Tidbyt device!

## Features

- 🎵 Shows a random album from your Discogs collection
- 🖼️ Displays album artwork (thumbnail)
- 📝 Shows artist name and album title (with marquee scrolling for long names)
- 🔢 Shows track count and total album duration
- ⏱️ Caches data to minimize API calls (6-hour refresh)
- 📂 Filters by folder ID (default `f_0` = all folders; `f_<id>` for a specific folder)
- 🔄 Retries until it finds a vinyl entry
- 📊 Optional "stats" carousel with album count, total duration, and average duration

## What You'll Need

1. **A Tidbyt device** (obviously!)
2. **Pixlet CLI** - Tidbyt's development tool
3. **A Discogs account** with some records in your collection
4. **A Discogs Personal Access Token**

## Setup Instructions

### Step 1: Install Pixlet

**macOS (with Homebrew):**
```bash
brew install tidbyt/tidbyt/pixlet
```

**Other platforms:**
Download from [Pixlet releases](https://github.com/tidbyt/pixlet/releases)

### Step 2: Get Your Discogs Personal Access Token

1. Log into [Discogs](https://www.discogs.com)
2. Go to **Settings** → **Developers** (or visit [discogs.com/settings/developers](https://www.discogs.com/settings/developers))
3. Click **"Generate new token"**
4. Copy the token - you'll need it to configure the app

### Step 3: Test the App Locally

<!--```bash
# Serve the app locally with your credentials
pixlet serve vinyl_roulette.star \
  --watch \
  -- username=YOUR_DISCOGS_USERNAME \
  -- token=YOUR_DISCOGS_TOKEN
```-->
```bash
# Serve the app locally with your credentials
pixlet serve vinyl_roulette.star --watch
```

Open http://localhost:8080 in your browser to see the preview.

### Step 4: Push to Your Tidbyt

First, get your Tidbyt device ID and API key from the Tidbyt mobile app:
- Open the app → Settings → Get API Key

<!--```bash
# Render the app
pixlet render vinyl_roulette.star \
  username=YOUR_DISCOGS_USERNAME \
  token=YOUR_DISCOGS_TOKEN

# Push to your device (one-time display)
pixlet push YOUR_DEVICE_ID vinyl_roulette.webp \
  --api-token YOUR_TIDBYT_API_TOKEN

# Or push with an installation ID for persistent rotation
pixlet push YOUR_DEVICE_ID vinyl_roulette.webp \
  --api-token YOUR_TIDBYT_API_TOKEN \
  --installation-id "discogs-vinyl"
```-->
```bash
# Render the app
pixlet render vinyl_roulette.star

# Push to your device (one-time display)
pixlet push YOUR_DEVICE_ID vinyl_roulette.webp \
  --api-token YOUR_TIDBYT_API_TOKEN

# Or push with an installation ID for persistent rotation
pixlet push YOUR_DEVICE_ID vinyl_roulette.webp \
  --api-token YOUR_TIDBYT_API_TOKEN \
  --installation-id "vinyl-roulette"
```

## Setting Up Automatic Updates (Every 6 Hours)

Since you want the vinyl to change every 6 hours, you'll need to set up a scheduled task.

### Option A: Using cron (macOS/Linux)

```bash
# Open crontab editor
crontab -e

# Add this line to run every 6 hours
0 */6 * * * cd /path/to/app && pixlet render vinyl_roulette.star credentials=YOUR_USERNAME:YOUR_PERSONAL_ACCESS_TOKEN && pixlet push YOUR_DEVICE_ID vinyl_roulette.webp --api-token YOUR_API_TOKEN --installation-id "vinyl-roulette"
```

### Option B: Submit to Community Apps

For automatic scheduled rendering without managing your own cron jobs, you can submit to [Tidbyt Community Apps](https://github.com/tidbyt/community). Once accepted, Tidbyt's servers handle the rendering/pushing automatically!

See: https://tidbyt.dev/docs/publish/community-apps

## How It Works

1. **First API call**: Fetches your collection metadata (total count)
2. **Random selection**: Picks a random page and item index
3. **Second API call**: Fetches that page of your collection
4. **Third API call**: Fetches full release details for track count/duration
5. **Caching**: Collection metadata cached for 6 hours, release details for 24 hours

## API Rate Limits

Discogs API allows:
- **60 requests/minute** for authenticated users
- The app makes 2-3 requests per refresh (well within limits)

## Customization Ideas

Want to customize? Here are some ideas:

- **Filter by format**: Only show LPs, 7"s, etc.<!--- **Show year**: Display the release year--><!--- **Different color schemes**: Modify the color values in the render functions-->
- **Animated transitions**: Add animation frames for smooth album changes

## Troubleshooting

**"Set Discogs username" error:**
- Make sure you're passing the username parameter correctly

**"API error: 401":**
- Your token may be invalid or expired
- Generate a new token at discogs.com/settings/developers

**"Collection is empty":**
- Make sure your Discogs collection has records
- Check that your collection privacy is set to public (or you're using the correct token)

**No album art showing:**
- Some releases don't have images
- The app falls back to text-only layout

## Files

- `vinyl_roulette.star` - The main app code
- `README.md` - This file

## Credits

- Discogs API: https://www.discogs.com/developers/
- Tidbyt/Pixlet: https://tidbyt.dev

---

Enjoy your random vinyl discoveries! 🎶
