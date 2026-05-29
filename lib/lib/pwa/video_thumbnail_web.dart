enum ImageFormat { JPEG, PNG, WEBP }

class VideoThumbnail {
  static Future<String?> thumbnailFile({
    required String video,
    String? thumbnailPath,
    ImageFormat imageFormat = ImageFormat.JPEG,
    int maxHeight = 0,
    int maxWidth = 0,
    int quality = 10,
    int timeMs = 0,
  }) async {
    return null;
  }
}
