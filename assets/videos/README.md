# Sample Stereoscopic Videos

This directory should contain sample side-by-side (SBS) stereoscopic videos for testing the depth map feature.

## Expected Format

The video should be in **Side-by-Side (SBS)** format:
- Two views stitched horizontally
- Each view is horizontally squashed by 2x
- The combined video has the same aspect ratio as either original view

Example: A stereo pair of 1920x1080 images becomes a 1920x1080 SBS video where:
- Left half (pixels 0-959): Squashed left camera view
- Right half (pixels 960-1919): Squashed right camera view

## Required File

Place a file named `sample_stereo.mp4` in this directory.

## Where to Get Sample Videos

1. **YouTube 3D content** - Download SBS 3D videos (ensure proper licensing)
2. **Archive.org** - Search for "stereoscopic" or "3D SBS" videos
3. **Create your own** - Use FFmpeg to create SBS from two synchronized camera feeds:
   ```bash
   ffmpeg -i left.mp4 -i right.mp4 -filter_complex "[0:v]scale=iw/2:ih[left];[1:v]scale=iw/2:ih[right];[left][right]hstack" output_sbs.mp4
   ```

## Supported Formats

- MP4 (H.264)
- MKV
- WebM
- Any format supported by media_kit
