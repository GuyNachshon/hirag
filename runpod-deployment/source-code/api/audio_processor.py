"""
Audio Processing Utilities for RAG System
Handles multi-format audio conversion for Whisper service
"""

import os
import tempfile
import subprocess
import logging
from pathlib import Path
from typing import Optional, Tuple, Union
import aiofiles
import librosa
import soundfile as sf
from pydub import AudioSegment
import numpy as np

logger = logging.getLogger(__name__)

class AudioProcessor:
    """Enhanced audio processor for multi-format support with Whisper optimization"""

    # Supported input formats
    SUPPORTED_FORMATS = {
        '.mp3', '.wav', '.m4a', '.ogg', '.flac',
        '.wma', '.aac', '.opus', '.webm', '.3gp'
    }

    # Target format for Whisper (Ivrit-AI optimized)
    TARGET_FORMAT = 'wav'
    TARGET_SAMPLE_RATE = 16000  # 16kHz for Whisper
    TARGET_CHANNELS = 1  # Mono

    def __init__(self, temp_dir: Optional[str] = None):
        self.temp_dir = temp_dir or tempfile.gettempdir()
        Path(self.temp_dir).mkdir(exist_ok=True)

    async def process_audio_file(
        self,
        file_path: Union[str, Path],
        target_format: str = TARGET_FORMAT,
        target_sample_rate: int = TARGET_SAMPLE_RATE,
        target_channels: int = TARGET_CHANNELS,
        normalize: bool = True,
        remove_silence: bool = True
    ) -> Tuple[str, dict]:
        """
        Process audio file for optimal Whisper performance

        Args:
            file_path: Path to input audio file
            target_format: Output format (default: wav)
            target_sample_rate: Target sample rate (default: 16000)
            target_channels: Number of channels (default: 1)
            normalize: Whether to normalize audio levels
            remove_silence: Whether to remove leading/trailing silence

        Returns:
            Tuple of (output_path, metadata)
        """
        file_path = Path(file_path)

        if not file_path.exists():
            raise FileNotFoundError(f"Audio file not found: {file_path}")

        if file_path.suffix.lower() not in self.SUPPORTED_FORMATS:
            raise ValueError(f"Unsupported audio format: {file_path.suffix}")

        # Generate output path
        output_path = Path(self.temp_dir) / f"processed_{file_path.stem}.{target_format}"

        try:
            # Get input file metadata
            metadata = await self._get_audio_metadata(file_path)
            logger.info(f"Processing audio: {metadata}")

            # Load audio using librosa for better processing
            audio_data, sample_rate = librosa.load(
                str(file_path),
                sr=target_sample_rate,
                mono=(target_channels == 1)
            )

            # Apply audio enhancements
            if normalize:
                audio_data = self._normalize_audio(audio_data)

            if remove_silence:
                audio_data = self._remove_silence(audio_data, sample_rate)

            # Apply Hebrew speech optimization
            audio_data = self._optimize_for_hebrew(audio_data, sample_rate)

            # Save processed audio
            sf.write(
                str(output_path),
                audio_data,
                sample_rate,
                format=target_format.upper(),
                subtype='PCM_16'
            )

            # Update metadata
            processed_metadata = {
                'original_file': str(file_path),
                'processed_file': str(output_path),
                'original_format': file_path.suffix.lower(),
                'target_format': target_format,
                'original_sample_rate': metadata.get('sample_rate'),
                'target_sample_rate': target_sample_rate,
                'original_channels': metadata.get('channels'),
                'target_channels': target_channels,
                'original_duration': metadata.get('duration'),
                'processed_duration': len(audio_data) / sample_rate,
                'file_size': output_path.stat().st_size,
                'processing_applied': {
                    'normalize': normalize,
                    'remove_silence': remove_silence,
                    'hebrew_optimization': True
                }
            }

            return str(output_path), processed_metadata

        except Exception as e:
            logger.error(f"Audio processing failed: {e}")
            # Fallback to FFmpeg conversion
            return await self._fallback_conversion(file_path, output_path, target_format)

    async def _get_audio_metadata(self, file_path: Path) -> dict:
        """Extract audio metadata using FFprobe"""
        try:
            # Use FFprobe for metadata
            cmd = [
                'ffprobe',
                '-v', 'quiet',
                '-print_format', 'json',
                '-show_format',
                '-show_streams',
                str(file_path)
            ]

            result = subprocess.run(cmd, capture_output=True, text=True, check=True)

            import json
            info = json.loads(result.stdout)

            # Extract audio stream info
            audio_stream = next(
                (s for s in info['streams'] if s['codec_type'] == 'audio'),
                {}
            )

            return {
                'duration': float(info['format'].get('duration', 0)),
                'sample_rate': int(audio_stream.get('sample_rate', 0)),
                'channels': int(audio_stream.get('channels', 0)),
                'codec': audio_stream.get('codec_name', 'unknown'),
                'bitrate': int(info['format'].get('bit_rate', 0))
            }

        except Exception as e:
            logger.warning(f"Could not extract metadata: {e}")
            return {}

    def _normalize_audio(self, audio_data: np.ndarray) -> np.ndarray:
        """Normalize audio levels"""
        # RMS-based normalization
        rms = np.sqrt(np.mean(audio_data**2))
        if rms > 0:
            target_rms = 0.1  # Target RMS level
            audio_data = audio_data * (target_rms / rms)

        # Peak normalization as safety
        peak = np.max(np.abs(audio_data))
        if peak > 0.95:
            audio_data = audio_data * (0.95 / peak)

        return audio_data

    def _remove_silence(self, audio_data: np.ndarray, sample_rate: int) -> np.ndarray:
        """Remove leading and trailing silence"""
        try:
            # Use librosa to trim silence
            audio_trimmed, _ = librosa.effects.trim(
                audio_data,
                top_db=20,  # dB below peak to consider as silence
                frame_length=2048,
                hop_length=512
            )
            return audio_trimmed
        except Exception as e:
            logger.warning(f"Silence removal failed: {e}")
            return audio_data

    def _optimize_for_hebrew(self, audio_data: np.ndarray, sample_rate: int) -> np.ndarray:
        """Apply Hebrew speech-specific optimizations"""
        try:
            # Apply pre-emphasis filter (common for speech recognition)
            pre_emphasis = 0.97
            audio_data = np.append(audio_data[0], audio_data[1:] - pre_emphasis * audio_data[:-1])

            # Apply gentle high-pass filter to remove low-frequency noise
            from scipy.signal import butter, filtfilt
            nyquist = sample_rate * 0.5
            low = 80 / nyquist  # 80Hz high-pass
            b, a = butter(5, low, btype='high')
            audio_data = filtfilt(b, a, audio_data)

            return audio_data
        except Exception as e:
            logger.warning(f"Hebrew optimization failed: {e}")
            return audio_data

    async def _fallback_conversion(self, input_path: Path, output_path: Path, target_format: str) -> Tuple[str, dict]:
        """Fallback conversion using FFmpeg"""
        try:
            cmd = [
                'ffmpeg',
                '-i', str(input_path),
                '-acodec', 'pcm_s16le',
                '-ar', str(self.TARGET_SAMPLE_RATE),
                '-ac', str(self.TARGET_CHANNELS),
                '-y',  # Overwrite output
                str(output_path)
            ]

            subprocess.run(cmd, check=True, capture_output=True)

            metadata = {
                'original_file': str(input_path),
                'processed_file': str(output_path),
                'conversion_method': 'ffmpeg_fallback',
                'target_sample_rate': self.TARGET_SAMPLE_RATE,
                'target_channels': self.TARGET_CHANNELS,
                'file_size': output_path.stat().st_size
            }

            return str(output_path), metadata

        except subprocess.CalledProcessError as e:
            logger.error(f"FFmpeg conversion failed: {e}")
            raise RuntimeError(f"Audio conversion failed: {e}")

    async def chunk_audio(
        self,
        file_path: str,
        chunk_duration: int = 30,
        overlap: int = 2
    ) -> list:
        """
        Split audio into chunks for processing large files

        Args:
            file_path: Path to audio file
            chunk_duration: Duration of each chunk in seconds
            overlap: Overlap between chunks in seconds

        Returns:
            List of chunk file paths
        """
        try:
            audio = AudioSegment.from_file(file_path)

            chunks = []
            chunk_length_ms = chunk_duration * 1000
            overlap_ms = overlap * 1000

            for i, start_ms in enumerate(range(0, len(audio), chunk_length_ms - overlap_ms)):
                end_ms = min(start_ms + chunk_length_ms, len(audio))

                chunk = audio[start_ms:end_ms]
                chunk_path = Path(self.temp_dir) / f"chunk_{i:03d}.wav"

                chunk.export(str(chunk_path), format="wav")
                chunks.append(str(chunk_path))

            return chunks

        except Exception as e:
            logger.error(f"Audio chunking failed: {e}")
            raise

    async def validate_audio_file(self, file_path: Union[str, Path]) -> bool:
        """Validate if file is a valid audio file"""
        try:
            file_path = Path(file_path)

            # Check file extension
            if file_path.suffix.lower() not in self.SUPPORTED_FORMATS:
                return False

            # Try to load metadata
            metadata = await self._get_audio_metadata(file_path)

            return (
                metadata.get('duration', 0) > 0 and
                metadata.get('sample_rate', 0) > 0 and
                metadata.get('channels', 0) > 0
            )

        except Exception:
            return False

    def cleanup_temp_files(self, file_paths: list):
        """Clean up temporary files"""
        for file_path in file_paths:
            try:
                Path(file_path).unlink(missing_ok=True)
            except Exception as e:
                logger.warning(f"Could not remove temp file {file_path}: {e}")

    @classmethod
    def get_supported_formats(cls) -> list:
        """Get list of supported audio formats"""
        return sorted(list(cls.SUPPORTED_FORMATS))

# Usage example and test function
async def test_audio_processor():
    """Test function for audio processor"""
    processor = AudioProcessor()

    # This would be used in your API endpoints
    try:
        # Example usage:
        # processed_path, metadata = await processor.process_audio_file("input.mp3")
        # print(f"Processed audio: {processed_path}")
        # print(f"Metadata: {metadata}")

        supported = processor.get_supported_formats()
        print(f"Supported formats: {supported}")

    except Exception as e:
        logger.error(f"Test failed: {e}")

if __name__ == "__main__":
    import asyncio
    asyncio.run(test_audio_processor())