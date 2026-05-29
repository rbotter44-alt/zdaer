import 'dart:io' as io;

import 'package:flutter/material.dart';

Widget pwaImageFile(String path, {BoxFit? fit, double? width, double? height}) {
  return Image.file(io.File(path), fit: fit, width: width, height: height);
}
