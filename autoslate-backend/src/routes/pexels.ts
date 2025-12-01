import { Router, Request, Response } from 'express';
import axios, { AxiosError } from 'axios';

const router = Router();

// Interface for normalized stock clip response
interface StockClip {
  id: string;
  provider: string;
  sourceId: number;
  width: number;
  height: number;
  duration: number;
  thumbnailUrl: string;
  downloadUrl: string;
  tags: string[];
  attribution: {
    providerName: string;
    url: string;
  };
}

interface StockSearchResponse {
  clips: StockClip[];
  page: number;
  per_page: number;
  total_results: number;
  next_page: string | null;
}

// Pexels API response interfaces
interface PexelsVideoFile {
  id: number;
  quality: string;
  file_type: string;
  width: number | null;
  height: number | null;
  link: string;
  fps: number | null;
}

interface PexelsVideo {
  id: number;
  width: number;
  height: number;
  duration: number;
  image: string;
  video_files: PexelsVideoFile[];
  url: string;
}

interface PexelsSearchResponse {
  page: number;
  per_page: number;
  total_results: number;
  videos: PexelsVideo[];
  next_page: string | null;
}

/**
 * Normalize Pexels video to StockClip format
 */
function normalizePexelsVideo(video: PexelsVideo, query: string): StockClip {
  // Find the best quality video file (prefer HD, fallback to highest resolution)
  let bestFile: PexelsVideoFile | null = null;
  
  // First try to find HD quality
  bestFile = video.video_files.find(f => f.quality === 'hd') || null;
  
  // If no HD, find the highest resolution
  if (!bestFile) {
    bestFile = video.video_files.reduce((best, current) => {
      const currentRes = (current.width || 0) * (current.height || 0);
      const bestRes = (best.width || 0) * (best.height || 0);
      return currentRes > bestRes ? current : best;
    });
  }
  
  // Fallback to first file if still no file found
  if (!bestFile && video.video_files.length > 0) {
    bestFile = video.video_files[0];
  }
  
  const downloadUrl = bestFile?.link || video.video_files[0]?.link || '';
  
  // Extract tags from query (simple approach - split on spaces)
  const tags = query
    .toLowerCase()
    .split(/\s+/)
    .filter(tag => tag.length > 2);
  
  return {
    id: `pexels_${video.id}`,
    provider: 'pexels',
    sourceId: video.id,
    width: video.width,
    height: video.height,
    duration: video.duration,
    thumbnailUrl: video.image,
    downloadUrl: downloadUrl,
    tags: tags,
    attribution: {
      providerName: 'Pexels',
      url: video.url || `https://www.pexels.com/video/${video.id}/`
    }
  };
}

/**
 * GET /api/stock/pexels/search
 * Search for stock videos from Pexels
 */
router.get('/search', async (req: Request, res: Response) => {
  try {
    // Check if API key is configured
    const apiKey = process.env.PEXELS_API_KEY;
    if (!apiKey) {
      return res.status(500).json({
        error: 'PEXELS_API_KEY_NOT_CONFIGURED',
        message: 'Pexels API key is not configured on the server'
      });
    }
    
    // Get query parameters
    const query = (req.query.query as string) || 'video';
    const page = parseInt(req.query.page as string) || 1;
    const perPage = parseInt(req.query.per_page as string) || 20;
    
    // Validate query
    if (typeof query !== 'string' || query.trim().length === 0) {
      return res.status(400).json({
        error: 'QUERY_REQUIRED',
        message: 'Query parameter is required and cannot be empty'
      });
    }
    
    // Build Pexels API URL
    const pexelsUrl = 'https://api.pexels.com/videos/search';
    const params = new URLSearchParams({
      query: query.trim(),
      page: page.toString(),
      per_page: perPage.toString()
    });
    
    // Make request to Pexels API
    try {
      const response = await axios.get<PexelsSearchResponse>(
        `${pexelsUrl}?${params.toString()}`,
        {
          headers: {
            'Authorization': apiKey
          }
        }
      );
      
      // Normalize response
      const normalizedClips: StockClip[] = response.data.videos.map(video =>
        normalizePexelsVideo(video, query)
      );
      
      const searchResponse: StockSearchResponse = {
        clips: normalizedClips,
        page: response.data.page,
        per_page: response.data.per_page,
        total_results: response.data.total_results,
        next_page: response.data.next_page
      };
      
      return res.json(searchResponse);
      
    } catch (pexelsError) {
      const axiosError = pexelsError as AxiosError;
      
      if (axiosError.response) {
        const status = axiosError.response.status;
        
        if (status === 401) {
          return res.status(502).json({
            error: 'PEXELS_REQUEST_FAILED',
            message: 'Invalid Pexels API key'
          });
        } else if (status === 429) {
          return res.status(502).json({
            error: 'PEXELS_REQUEST_FAILED',
            message: 'Pexels API rate limit exceeded'
          });
        } else {
          return res.status(502).json({
            error: 'PEXELS_REQUEST_FAILED',
            message: `Pexels API returned error: ${status}`
          });
        }
      }
      
      return res.status(502).json({
        error: 'PEXELS_REQUEST_FAILED',
        message: 'Failed to communicate with Pexels API'
      });
    }
    
  } catch (error) {
    console.error('Error in Pexels search route:', error);
    return res.status(500).json({
      error: 'INTERNAL_SERVER_ERROR',
      message: 'An unexpected error occurred'
    });
  }
});

export { router as pexelsRouter };

