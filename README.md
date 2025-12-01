# AutoSlate (SkipSlate)

AutoSlate is a macOS video editing application that uses AI-powered auto-editing to create professional highlight reels, podcasts, documentaries, music videos, and dance videos.

## Features

- **Auto-Edit**: AI-powered automatic video editing with beat detection and visual moment analysis
- **Multiple Project Types**: Support for highlight reels, podcasts, documentaries, music videos, and dance videos
- **Real-time Preview**: Live preview with playback controls
- **Export**: High-quality video export with customizable resolution and quality settings
- **Stock Media Integration**: Pexels API integration for stock videos and photos (coming soon)

## Requirements

- macOS 13.0 or later
- Xcode 15.0 or later
- Swift 5.9 or later

## Setup

### 1. Clone the Repository

```bash
git clone https://github.com/quickpayplatform/AutoSlate.git
cd AutoSlate
```

### 2. Open in Xcode

```bash
open SkipSlate.xcodeproj
```

### 3. Configure Pexels API (Optional)

1. Get your API key from [Pexels API](https://www.pexels.com/api/)
2. Copy `.env.example` to `.env`:
   ```bash
   cp .env.example .env
   ```
3. Edit `.env` and add your API key:
   ```
   PEXELS_API_KEY=your_pexels_api_key_here
   ```
4. The `.env` file is already in `.gitignore` and won't be committed to the repository.

Alternatively, you can set the API key as an environment variable:
```bash
export PEXELS_API_KEY=your_pexels_api_key_here
```

Or configure it programmatically in the app:
```swift
PexelsService.shared.setAPIKey("your_pexels_api_key_here")
```

## Building

1. Open `SkipSlate.xcodeproj` in Xcode
2. Select your target device or simulator
3. Press `Cmd + B` to build
4. Press `Cmd + R` to run

## Project Structure

```
SkipSlate/
├── Models/           # Data models (Project, Segment, Clip, etc.)
├── ViewModels/       # View models for MVVM architecture
├── Views/            # SwiftUI views
├── Services/         # Business logic services
│   ├── AutoEditService.swift
│   ├── ExportService.swift
│   ├── PexelsService.swift
│   └── ...
└── Resources/        # Assets, images, etc.
```

## Services

### PexelsService

The `PexelsService` provides integration with the Pexels API for searching and downloading stock videos and photos.

**Usage:**
```swift
// Search videos
let response = try await PexelsService.shared.searchVideos(
    query: "nature",
    page: 1,
    perPage: 15
)

// Search photos
let photoResponse = try await PexelsService.shared.searchPhotos(
    query: "mountains",
    page: 1,
    perPage: 15
)

// Download video
let videoURL = try await PexelsService.shared.downloadVideo(from: videoURL)

// Download photo
let photoURL = try await PexelsService.shared.downloadPhoto(from: photoURL)
```

## Configuration

### Environment Variables

The app supports the following environment variables (set via `.env` file or system environment):

- `PEXELS_API_KEY`: Your Pexels API key (required for Pexels features)
- `PEXELS_API_BASE_URL`: API base URL (default: https://api.pexels.com/v1)
- `PEXELS_RATE_LIMIT_PER_MINUTE`: Rate limit per minute (default: 200)
- `PEXELS_DOWNLOAD_QUALITY`: Download quality (default: original)

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

[Add your license here]

## Support

For issues, questions, or contributions, please open an issue on GitHub.

