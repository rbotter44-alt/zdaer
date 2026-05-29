import 'package:flutter/material.dart';

Widget pwaImageFile(String path, {BoxFit? fit, double? width, double? height}) {
  return Container(
    width: width,
    height: height,
    alignment: Alignment.center,
    color: Colors.black26,
    child: const Icon(Icons.movie_creation_outlined, color: Colors.white54),
  );
}
