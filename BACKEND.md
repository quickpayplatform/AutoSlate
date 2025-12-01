# AutoSlate Backend Setup

This document describes how to set up and run the AutoSlate backend server for Pexels stock video integration.

## Overview

The backend server acts as a secure proxy between the AutoSlate macOS app and the Pexels API. This ensures that:

- The Pexels API key is kept secret on the server (never exposed to the client)
- The `.env` file with the API key is never committed to git
- All Pexels API communication happens server-side

## Prerequisites

- Node.js (v18 or higher recommended)
- npm (comes with Node.js)
- A Pexels API key (get one from https://www.pexels.com/api/)

## Setup Instructions

### 1. Install Dependencies

Navigate to the `autoslate-backend` directory and install dependencies:

```bash
cd autoslate-backend
npm install
```

### 2. Configure Environment Variables

Create a `.env` file in the `autoslate-backend` directory:

```bash
cp .env.example .env
```

Then edit `.env` and replace `REPLACE_WITH_REAL_KEY` with your actual Pexels API key:

```env
PEXELS_API_KEY=your_actual_api_key_here
PORT=4000
```

**IMPORTANT:** The `.env` file is gitignored and should NEVER be committed to version control.

### 3. Start the Backend Server

For development (with auto-reload):

```bash
npm run dev
```

For production:

```bash
npm run build
npm start
```

The server will start on `http://localhost:4000` (or the port specified in `.env`).

### 4. Verify the Server is Running

Open your browser and navigate to:

```
http://localhost:4000/health
```

You should see:

```json
{
  "status": "ok",
  "service": "autoslate-backend"
}
```

## API Endpoints

### GET /api/stock/pexels/search

Search for stock videos from Pexels.

**Query Parameters:**
- `query` (string, required): Search query (e.g., "cinematic", "nature", "city")
- `page` (number, optional, default: 1): Page number for pagination
- `per_page` (number, optional, default: 20): Number of results per page (max: 80)

**Example Request:**
```
GET http://localhost:4000/api/stock/pexels/search?query=cinematic&page=1&per_page=20
```

**Example Response:**
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

## Client Configuration

The AutoSlate macOS app is configured to connect to `http://localhost:4000` by default. To change this:

1. Set the `AUTO_SLATE_API_BASE_URL` environment variable when launching the app, or
2. Use the `StockService.setBackendURL(_:)` method in code

## Security Notes

- ✅ The `.env` file is gitignored
- ✅ The API key is never exposed to the client
- ✅ All Pexels API calls happen server-side
- ✅ CORS is enabled for local development
- ⚠️ For production, configure CORS to only allow requests from your app's domain

## Troubleshooting

### Server won't start

- Check that Node.js is installed: `node --version`
- Check that port 4000 (or your configured port) is not already in use
- Verify the `.env` file exists and contains `PEXELS_API_KEY`

### API returns 500 error

- Check the server console for error messages
- Verify `PEXELS_API_KEY` is set correctly in `.env`
- Test the API key directly with Pexels API documentation

### Client can't connect to backend

- Verify the backend server is running
- Check the backend URL in the client configuration
- Ensure network permissions are enabled in the macOS app entitlements

## Development

### Project Structure

```
autoslate-backend/
├── src/
│   ├── index.ts          # Main server entry point
│   └── routes/
│       └── pexels.ts     # Pexels API route handler
├── .env                  # Environment variables (gitignored)
├── .env.example          # Example environment file
├── .gitignore           # Git ignore rules
├── package.json         # Node.js dependencies
├── tsconfig.json        # TypeScript configuration
└── README.md            # This file
```

### Building for Production

```bash
npm run build
```

This compiles TypeScript to JavaScript in the `dist/` directory.

### TypeScript

The backend uses TypeScript for type safety. The configuration is in `tsconfig.json`.

## License

This backend is part of the AutoSlate project. Stock videos are provided by Pexels under their license terms.

