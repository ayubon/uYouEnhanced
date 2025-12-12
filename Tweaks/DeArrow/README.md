# DeArrow Integration for uYouEnhanced

This tweak integrates [DeArrow](https://dearrow.ajay.app) into the YouTube iOS app, replacing clickbait titles and thumbnails with community-sourced alternatives.

## What is DeArrow?

DeArrow is a browser extension and API that provides:
- **Community-sourced video titles** - Replace clickbait with accurate, descriptive titles
- **Community-sourced thumbnails** - Replace misleading thumbnails with representative video frames

Created by [Ajay Ramachandran](https://github.com/ajayyy), the same developer behind SponsorBlock.

## Features

- ✅ Replace clickbait titles in home feed, search, and subscriptions
- ✅ Replace clickbait titles on the video watch page
- ✅ Replace thumbnails with community-chosen video frames
- ✅ In-memory caching to reduce API calls
- ✅ Respects user preferences (toggle titles/thumbnails separately)
- ✅ Graceful fallback when DeArrow has no data for a video

## API Usage

This integration uses the DeArrow API at `https://sponsor.ajay.app/api/branding`.

### License Compliance

- **API**: Free for non-browser extensions ✅
- **Database**: CC BY-NC-SA 4.0 (Attribution-NonCommercial-ShareAlike)
- **No automated submissions**: This integration only reads data

### Attribution

DeArrow data is provided by:
- **Creator**: Ajay Ramachandran
- **Website**: https://dearrow.ajay.app
- **GitHub**: https://github.com/ajayyy/DeArrow
- **API Docs**: https://wiki.sponsor.ajay.app/w/API_Docs/DeArrow

## Settings

| Setting | Default | Description |
|---------|---------|-------------|
| Enable DeArrow | ON | Master toggle |
| Replace Titles | ON | Use community-sourced titles |
| Replace Thumbnails | ON | Use community-sourced thumbnails |
| Apply in Feed | ON | Apply in home, search, subscriptions |
| Apply on Watch Page | ON | Apply on video player page |

## Technical Details

### API Endpoint

```
GET https://sponsor.ajay.app/api/branding/{hashPrefix}
```

Where `hashPrefix` is the first 4 characters of the SHA256 hash of the video ID (for privacy).

### Response Format

```json
{
  "VIDEO_ID": {
    "titles": [
      {
        "title": "Actual Descriptive Title",
        "original": false,
        "votes": 10,
        "locked": false
      }
    ],
    "thumbnails": [
      {
        "timestamp": 120.5,
        "original": false,
        "votes": 5
      }
    ]
  }
}
```

## Building

This tweak is built as part of uYouEnhanced. See the main repository's build instructions.

## Credits

- **DeArrow**: Ajay Ramachandran (https://github.com/ajayyy)
- **uYouEnhanced**: arichornlover and contributors
- **Integration**: Based on patterns from iSponsorBlock

