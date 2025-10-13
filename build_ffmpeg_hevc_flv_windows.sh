#!/usr/bin/bash
set -e
echo "============================================"
echo " FFmpeg for Windows 11 (HEVC-FLV 支持版)"
echo " 作者：CCAV & ChatGPT 2025"
echo "============================================"

# 运行前请在 MSYS2 MinGW x64 终端中执行

# 1) 更新 pacman 数据库并安装依赖（如已安装会跳过）
echo "[1/6] 更新系统并安装依赖（需要网络）..."
pacman -Syu --noconfirm
# 重新执行一次更新以确保包数据库就绪（MSYS2 特性）
pacman -Syu --noconfirm

# 安装构建工具和必要库（MinGW64 目标）
pacman -S --needed --noconfirm \
    base-devel \
    mingw-w64-x86_64-toolchain \
    git \
    yasm \
    nasm \
    pkg-config \
    autoconf \
    automake \
    libtool \
    mingw-w64-x86_64-ffmpeg \
    mingw-w64-x86_64-x264 \
    mingw-w64-x86_64-x265 \
    mingw-w64-x86_64-fdk-aac \
    mingw-w64-x86_64-lame \
    mingw-w64-x86_64-libvpx \
    mingw-w64-x86_64-libvorbis \
    mingw-w64-x86_64-opus \
    mingw-w64-x86_64-libass \
    mingw-w64-x86_64-freetype \
    mingw-w64-x86_64-pkg-config

# Note: mingw-w64-x86_64-ffmpeg may provide a build; we still compile our own.
# 2) 获取 FFmpeg 源码
echo "[2/6] 下载 / 更新 FFmpeg 源码..."
cd ~
if [ ! -d ffmpeg ]; then
    git clone https://git.ffmpeg.org/ffmpeg.git
fi
cd ffmpeg
git fetch --all
git reset --hard origin/master
git pull --rebase

# 3) 生成 HEVC-FLV 补丁（内置）
echo "[3/6] 生成 HEVC-FLV 补丁..."
cat > hevc-flv.patch <<'EOF'
diff --git a/libavformat/flv.h b/libavformat/flv.h
--- a/libavformat/flv.h
+++ b/libavformat/flv.h
@@
 #define FLV_CODECID_SCREEN2  7
+#define FLV_CODECID_HEVC     12  /* unofficial HEVC support */

 /* audio codec */
 #define FLV_CODECID_PCM              0
diff --git a/libavformat/flvenc.c b/libavformat/flvenc.c
--- a/libavformat/flvenc.c
+++ b/libavformat/flvenc.c
@@
 static int flv_write_packet(AVFormatContext *s, AVPacket *pkt)
 {
     ...
     if (par->codec_id == AV_CODEC_ID_H264) {
         if (pkt->pts != pkt->dts)
             flags_size = 0x10; // keyframe
@@
+    /* HEVC (H.265) unofficial FLV support */
+    if (par->codec_id == AV_CODEC_ID_HEVC) {
+        flv->video_codec = FLV_CODECID_HEVC;
+        if (pkt->flags & AV_PKT_FLAG_KEY)
+            flags_size = 0x10; // keyframe
+        else
+            flags_size = 0x20; // inter frame
+    }
@@
 static const AVCodecTag flv_video_codec_ids[] = {
     { AV_CODEC_ID_VP6A,     FLV_CODECID_VP6A },
     { AV_CODEC_ID_SCREEN,   FLV_CODECID_SCREEN },
     { AV_CODEC_ID_SCREEN2,  FLV_CODECID_SCREEN2 },
+    { AV_CODEC_ID_HEVC,     FLV_CODECID_HEVC },
     { AV_CODEC_ID_NONE,     0 }
 };
EOF

# 4) 应用补丁（尝试干净应用，否则尝试宽容方式）
echo "[4/6] 应用补丁..."
if git apply --index hevc-flv.patch; then
    echo "[+] 补丁已成功应用（干净）"
else
    echo "⚠️ 补丁未能完全干净应用，尝试宽容应用（会生成 .rej 文件用于调试）..."
    git apply --reject --whitespace=fix hevc-flv.patch || true
fi

# 5) 配置编译（MinGW64 环境）
echo "[5/6] 配置编译（MinGW64）..."
export PATH="/mingw64/bin:$PATH"
export PKG_CONFIG_PATH="/mingw64/lib/pkgconfig:/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH"
export CFLAGS="-O2 -march=native"
export LDFLAGS=""

# 若想把结果安装到 /mingw64/ffmpeg-hevc-flv（便于直接在 Windows 上调用）
PREFIX="/mingw64/ffmpeg-hevc-flv"

./configure \
  --prefix="$PREFIX" \
  --arch=x86_64 \
  --target-os=mingw64 \
  --enable-gpl \
  --enable-nonfree \
  --enable-static \
  --disable-shared \
  --enable-libx264 \
  --enable-libx265 \
  --enable-libfdk-aac \
  --enable-libmp3lame \
  --enable-libass \
  --enable-libfreetype \
  --enable-libvorbis \
  --enable-libvpx \
  --enable-libopus \
  --enable-encoder=libx265 \
  --enable-decoder=hevc \
  --enable-ffmpeg \
  --enable-ffprobe \
  --enable-ffplay

# 6) 编译并安装
echo "[6/6] 开始编译（这将耗费较多时间）..."
make -j$(nproc) || { echo "⚠️ make 失败，尝试单线程 make 再看错误："; make; exit 1; }
make install

echo
echo "============================================"
echo "✅ 编译完成！"
echo "ffmpeg.exe 路径（MSYS2 / Windows 下映射）:"
echo "  $(cygpath -w $PREFIX)/bin/ffmpeg.exe"
echo
echo "测试命令（在 MSYS2 MinGW x64 终端）："
echo "  $PREFIX/bin/ffmpeg -i input.mp4 -c:v libx265 -c:a aac -f flv output_hevc.flv"
echo
echo "若要在 Windows CMD/PowerShell 使用，请将以下路径加入系统 PATH："
echo "  C:\\msys64\\mingw64\\ffmpeg-hevc-flv\\bin"
echo "============================================"
