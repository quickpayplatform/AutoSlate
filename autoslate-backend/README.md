# AutoSlate Backend

Backend server for AutoSlate app providing Pexels stock video integration.

## Setup

1. Install dependencies:
   ```bash
   npm install
   ```

2. Configure environment variables:
   - Copy `.env.example` to `.env`
   - Replace `REPLACE_WITH_REAL_KEY` with your actual Pexels API key
   - Get your API key from https://www.pexels.com/api/

3. Run the development server:
   ```bash
   npm run dev
   ```

   The server will start on `http://localhost:4000` (or the port specified in `.env`)

## API Endpoints

### GET /api/stock/pexels/search

Search for stock videos from Pexels.

**Query Parameters:**
- `query` (string, required): Search query
- `page` (number, optional, default: 1): Page number
- `per_page` (number, optional, default: 20): Results per page

**Example:**
```
GET /api/stock/pexels/search?query=cinematic&page=1&per_page=20
```

**Response:**
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

## Security

- The `.env` file is gitignored and should NEVER be committed
- The Pexels API key is kept secret on the backend
- The client app communicates with this backend, not directly with Pexels

