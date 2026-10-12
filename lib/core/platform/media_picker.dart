import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

enum PickedMediaType { image, video }

final class PickedMedia {
  const PickedMedia({
    required this.path,
    required this.type,
    required this.originalFilename,
  });

  factory PickedMedia.image(String path, {String? originalFilename}) =>
      PickedMedia(
        path: path,
        type: PickedMediaType.image,
        originalFilename: originalFilename ?? p.basename(path),
      );

  factory PickedMedia.video(String path, {String? originalFilename}) =>
      PickedMedia(
        path: path,
        type: PickedMediaType.video,
        originalFilename: originalFilename ?? p.basename(path),
      );

  final String path;
  final PickedMediaType type;
  final String originalFilename;
}

abstract interface class MediaPicker {
  Future<List<PickedMedia>> pickImages();
  Future<PickedMedia?> pickVideo();
}

final class ImagePickerMediaPicker implements MediaPicker {
  ImagePickerMediaPicker({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<List<PickedMedia>> pickImages() async {
    final picked = await _picker.pickMultiImage();
    return picked
        .map(
          (file) => PickedMedia.image(file.path, originalFilename: file.name),
        )
        .toList(growable: false);
  }

  @override
  Future<PickedMedia?> pickVideo() async {
    final picked = await _picker.pickVideo(source: ImageSource.gallery);
    return picked == null
        ? null
        : PickedMedia.video(picked.path, originalFilename: picked.name);
  }
}
