# Pexels API Setup Guide

## API Key Configuration

The Pexels API key has been provided: `lT0iQhHJZ7YjXBjVYYu8cOuBNRWULF2gXLGwvK53AdjUbzVM0hy7cBkw`

**⚠️ IMPORTANT: Never commit the API key to git!**

## Backend Server Setup (Node.js/Express)

The backend server is located in `autoslate-backend/`. To set it up:

1. Navigate to the backend directory:
   ```bash
   cd autoslate-backend
   ```

2. Install dependencies:
   ```bash
   npm install
   ```

3. Create a `.env` file in the `autoslate-backend/` directory:
   ```bash
   cp .env.example .env
   ```

4. Edit `.env` and add your API key:
   ```
   PEXELS_API_KEY=lT0iQhHJZ7YjXBjVYYu8cOuBNRWULF2gXLGwvK53AdjUbzVM0hy7cBkw
   PORT=4000
   ```

5. Start the backend server:
   ```bash
   npm run dev
   ```

The server will run on `http://localhost:4000` (or the port specified in `.env`).

### Backend API Endpoints

- `GET /health` - Health check endpoint
- `GET /api/stock/pexels/search?query=cinematic&page=1&per_page=20` - Search for stock videos

## Swift Client Setup (Optional Direct Integration)

If you want to use the Swift `PexelsService` directly (bypassing the backend), you can:

1. Set the API key programmatically:
   ```swift
   PexelsService.shared.setAPIKey("lT0iQhHJZ7YjXBjVYYu8cOuBNRWULF2gXLGwvK53AdjUbzVM0hy7cBkw")
   ```

2. Or set it as an environment variable:
   ```bash
   export PEXELS_API_KEY=lT0iQhHJZ7YjXBjVYYu8cOuBNRWULF2gXLGwvK53AdjUbzVM0hy7cBkw
   ```

3. Or create a `.env` file in the project root with:
   ```
   PEXELS_API_KEY=lT0iQhHJZ7YjXBjVYYu8cOuBNRWULF2gXLGwvK53AdjUbzVM0hy7cBkw
   ```

## Recommended Architecture

The backend server approach is recommended because:
- Keeps API keys secure on the server
- Provides rate limiting and caching
- Allows for future expansion with other stock media providers
- Centralizes API key management

## Testing

To test the backend is working:

```bash
curl http://localhost:4000/health
curl "http://localhost:4000/api/stock/pexels/search?query=nature&page=1&per_page=5"
```

