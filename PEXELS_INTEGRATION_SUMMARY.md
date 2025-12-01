# Pexels Stock Video Integration - Implementation Summary

## Overview

Full Pexels stock video integration has been implemented for the AutoSlate app. Users can now search for stock videos from within the app, and imported videos are added to the local media library just like user-uploaded files.

## Architecture

### Backend (Node.js + Express + TypeScript)

**Location:** `autoslate-backend/`

- **Purpose:** Secure proxy server that keeps the Pexels API key secret
- **API Endpoint:** `GET /api/stock/pexels/search`
- **Port:** 4000 (configurable via `.env`)

**Key Features:**
- ✅ API key stored securely in `.env` file (never committed to git)
- ✅ Normalizes Pexels API responses to a consistent format
- ✅ Error handling for API failures
- ✅ CORS enabled for local development

### Client (Swift/macOS)

**New Files:**
- `Models/StockClip.swift` - Data models for stock clips
- `Services/StockService.swift` - Service for communicating with backend

**Modified Files:**
- `Views/MediaImportStepView.swift` - Added "Stock" tab with search UI
- `SkipSlate.entitlements` - Added network client permission

## Setup Instructions

### 1. Backend Setup

```bash
cd autoslate-backend
npm install
```

Create `.env` file:
```env
PEXELS_API_KEY=lT0iQhHJZ7YjXBjVYYu8cOuBNRWULF2gXLGwvK53AdjUbzVM0hy7cBkw
PORT=4000
```

Start the server:
```bash
npm run dev
```

### 2. Client Setup

The macOS app is already configured to connect to `http://localhost:4000` by default. No additional configuration needed.

## User Experience

### Stock Video Search

1. **Access:** In the Media Import step, users see two tabs: "My Media" and "Stock"
2. **Search:** Click the "Stock" tab to access stock video search
3. **Default Query:** Initial search loads "cinematic b-roll" videos
4. **Custom Search:** Users can type any search query and click "Search"
5. **Results:** Videos are displayed in a grid with thumbnails, duration, and resolution
6. **Import:** Click "Import" on any video to download and add it to the media library

### Import Flow

1. User clicks "Import" on a stock video
2. Video is downloaded from Pexels to a temporary file
3. File is automatically imported using the existing `MediaImportService`
4. Video appears in "My Media" tab and can be used in the timeline

## Security

- ✅ Pexels API key is stored in backend `.env` file (never in client code)
- ✅ `.env` is gitignored and will never be committed
- ✅ Client communicates with backend, not directly with Pexels
- ✅ Network permissions properly configured in app entitlements

## Attribution

The Stock search UI includes proper attribution:
- Footer text: "Stock videos provided by Pexels"
- "Pexels" is a clickable link to https://www.pexels.com

## API Response Format

The backend normalizes Pexels responses to this format:

```json
{
  "clips": [
    {
      "id": "pexels_1234567",
      "provider": "pexels",
      "sourceId": 1234567,
      "width": 1920,
      "height": 1080,
      "duration": 12.3,
      "thumbnailUrl": "https://images.pexels.com/...",
      "downloadUrl": "https://player.pexels.com/external/...",
      "tags": ["cinematic"],
      "attribution": {
        "providerName": "Pexels",
        "url": "https://www.pexels.com/video/1234567/"
      }
    }
  ],
  "page": 1,
  "per_page": 20,
  "total_results": 100,
  "next_page": "https://api.pexels.com/videos/search?page=2&..."
}
```

## Files Created/Modified

### Backend
- `autoslate-backend/package.json`
- `autoslate-backend/tsconfig.json`
- `autoslate-backend/.gitignore`
- `autoslate-backend/.env.example`
- `autoslate-backend/README.md`
- `autoslate-backend/src/index.ts`
- `autoslate-backend/src/routes/pexels.ts`

### Client
- `SkipSlate/Models/StockClip.swift` (new)
- `SkipSlate/Services/StockService.swift` (new)
- `SkipSlate/Views/MediaImportStepView.swift` (modified - added Stock tab)
- `SkipSlate/SkipSlate.entitlements` (modified - added network permission)

## Testing Checklist

- [ ] Backend server starts successfully
- [ ] Backend health check endpoint responds
- [ ] Stock search returns results
- [ ] Stock videos display with thumbnails
- [ ] Video download works
- [ ] Imported videos appear in "My Media"
- [ ] Imported videos can be added to timeline
- [ ] Attribution text is visible
- [ ] Error handling works (no API key, network errors, etc.)

## Next Steps

1. **Start the backend server:**
   ```bash
   cd autoslate-backend
   npm install
   # Create .env file with API key
   npm run dev
   ```

2. **Run the macOS app** and navigate to Media Import step

3. **Test the Stock tab:**
   - Verify default search loads results
   - Try custom search queries
   - Import a video and verify it appears in "My Media"

## Notes

- The existing `PexelsService.swift` file remains in the codebase but is not used by the Stock integration (which uses `StockService.swift` instead)
- Backend defaults to `localhost:4000` but can be configured via environment variable or UserDefaults
- Video files are downloaded to temporary directory and then imported through the standard media import flow

