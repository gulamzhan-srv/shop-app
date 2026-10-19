// Фото товаров: берём с камеры или из галереи, сжимаем до 200 КБ,
// сохраняем в папку приложения отдельным файлом (в базе — только имя файла).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/repo.dart';

class PhotoService {
  PhotoService._();
  static final PhotoService instance = PhotoService._();

  /// Максимальный размер одного фото.
  static const maxBytes = 200 * 1024;

  final _picker = ImagePicker();
  Directory? _dir;

  /// Папка с фото внутри приложения.
  Future<Directory> photosDir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(base.path, 'photos'));
    if (!await d.exists()) await d.create(recursive: true);
    return _dir = d;
  }

  Future<File> fileFor(String fileName) async => File(p.join((await photosDir()).path, fileName));

  /// Выбрать фото. fromCamera = true — камера, иначе галерея.
  /// Возвращает имя сохранённого файла или null, если пользователь отменил.
  Future<String?> pick({required bool fromCamera}) async {
    final x = await _picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (x == null) return null;
    final bytes = await _compress(await x.readAsBytes());
    final name = '${Repo.instance.newId()}.jpg';
    await (await fileFor(name)).writeAsBytes(bytes, flush: true);
    return name;
  }

  /// Сжимаем, пока не станет ≤ 200 КБ: сначала снижаем качество, потом размер.
  Future<Uint8List> _compress(Uint8List src) async {
    var side = 1280;
    var quality = 85;
    Uint8List out = src;
    for (var i = 0; i < 12; i++) {
      out = await FlutterImageCompress.compressWithList(
        src,
        minWidth: side,
        minHeight: side,
        quality: quality,
        format: CompressFormat.jpeg,
      );
      if (out.lengthInBytes <= maxBytes) return out;
      if (quality > 50) {
        quality -= 10;
      } else {
        side = (side * 0.8).round();
      }
    }
    return out; // на практике сюда почти не доходит
  }

  Future<void> deleteFile(String fileName) async {
    final f = await fileFor(fileName);
    if (await f.exists()) await f.delete();
  }
}
