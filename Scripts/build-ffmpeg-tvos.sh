#!/bin/bash
set -e

# FFmpeg build script for tvOS (arm64)
# Produces static libraries in Vendor/FFmpeg/

FFMPEG_VERSION="7.1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/Vendor/FFmpeg/build"
OUTPUT_DIR="$PROJECT_DIR/Vendor/FFmpeg"
SOURCE_DIR="$BUILD_DIR/ffmpeg-$FFMPEG_VERSION"

TVOS_MIN_VERSION="16.0"
TVOS_SDK=$(xcrun --sdk appletvos --show-sdk-path)
TVOS_SIM_SDK=$(xcrun --sdk appletvsimulator --show-sdk-path)

echo "=== Building FFmpeg $FFMPEG_VERSION for tvOS ==="
echo "SDK: $TVOS_SDK"
echo "Output: $OUTPUT_DIR"

# Download FFmpeg source
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

if [ ! -d "$SOURCE_DIR" ]; then
    echo "Downloading FFmpeg $FFMPEG_VERSION..."
    curl -L "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz" -o "ffmpeg-$FFMPEG_VERSION.tar.xz"
    tar xf "ffmpeg-$FFMPEG_VERSION.tar.xz"
fi

build_arch() {
    local PLATFORM=$1
    local SDK=$2
    local PREFIX="$BUILD_DIR/output-$PLATFORM"
    local CC=$(xcrun -sdk appletvos -find clang)

    echo "=== Building for $PLATFORM ==="
    cd "$SOURCE_DIR"
    make clean 2>/dev/null || true

    ./configure \
        --prefix="$PREFIX" \
        --enable-cross-compile \
        --arch=arm64 \
        --target-os=darwin \
        --cc="$CC" \
        --sysroot="$SDK" \
        --extra-cflags="-arch arm64 -mappletvos-version-min=$TVOS_MIN_VERSION -isysroot $SDK -fembed-bitcode" \
        --extra-ldflags="-arch arm64 -mappletvos-version-min=$TVOS_MIN_VERSION -isysroot $SDK" \
        --disable-programs \
        --disable-doc \
        --disable-debug \
        --disable-autodetect \
        --enable-pic \
        --enable-static \
        --disable-shared \
        --enable-small \
        \
        --enable-demuxer=matroska,mov,avi,mpegts,webm_dash_manifest,flv,ogg,wav,mp3,aac,flac \
        --enable-demuxer=srt,ass,webvtt \
        --enable-muxer=null \
        \
        --enable-decoder=aac,ac3,eac3,dts,flac,opus,mp3,truehd,vorbis \
        --enable-decoder=pcm_s16le,pcm_s24le,pcm_f32le,pcm_alaw,pcm_mulaw \
        --enable-decoder=h264,hevc,mpeg2video,mpeg4,vp8,vp9,av1,theora,vc1,wmv3 \
        --enable-decoder=srt,ass,ssa,webvtt,subrip,pgssub,dvdsub,dvbsub \
        \
        --enable-parser=h264,hevc,aac,ac3,dts,flac,opus,mpegaudio,vorbis,vp8,vp9,av1 \
        \
        --enable-protocol=http,https,file,tcp,tls \
        --enable-securetransport \
        \
        --enable-filter=aresample,aformat,anull,null \
        \
        --enable-swresample \
        --enable-avformat \
        --enable-avcodec \
        --enable-avutil \
        --disable-swscale \
        --disable-avdevice \
        --disable-avfilter \
        --disable-postproc \
        \
        --enable-videotoolbox \
        --enable-hwaccel=h264_videotoolbox,hevc_videotoolbox

    make -j$(sysctl -n hw.ncpu)
    make install
}

# Build for tvOS device (arm64)
build_arch "appletvos" "$TVOS_SDK"

# Copy output
echo "=== Copying libraries and headers ==="
DEVICE_PREFIX="$BUILD_DIR/output-appletvos"

rm -rf "$OUTPUT_DIR/lib" "$OUTPUT_DIR/include"
cp -r "$DEVICE_PREFIX/lib" "$OUTPUT_DIR/lib"
cp -r "$DEVICE_PREFIX/include" "$OUTPUT_DIR/include"

echo "=== Creating module map ==="
cat > "$OUTPUT_DIR/CFFmpeg/module.modulemap" << 'MODULEMAP'
module CFFmpeg [system] {
    header "../include/libavformat/avformat.h"
    header "../include/libavcodec/avcodec.h"
    header "../include/libavutil/avutil.h"
    header "../include/libavutil/pixdesc.h"
    header "../include/libavutil/hwcontext.h"
    header "../include/libavutil/hwcontext_videotoolbox.h"
    header "../include/libavutil/channel_layout.h"
    header "../include/libavutil/opt.h"
    header "../include/libavutil/imgutils.h"
    header "../include/libavutil/mathematics.h"
    header "../include/libavutil/time.h"
    header "../include/libswresample/swresample.h"
    link "avformat"
    link "avcodec"
    link "avutil"
    link "swresample"
    link "z"
    link "bz2"
    link "iconv"
    export *
}
MODULEMAP

echo "=== Done! ==="
echo "Libraries: $OUTPUT_DIR/lib/"
ls -la "$OUTPUT_DIR/lib/"*.a 2>/dev/null || echo "No .a files found"
echo ""
echo "Next steps:"
echo "1. Add Vendor/FFmpeg/lib to Library Search Paths in Xcode"
echo "2. Add Vendor/FFmpeg/include to Header Search Paths"
echo "3. Add Vendor/FFmpeg/CFFmpeg to Swift Import Paths"
echo "4. Link the .a files in Build Phases"
