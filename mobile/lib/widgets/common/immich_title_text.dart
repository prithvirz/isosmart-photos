import 'package:flutter/material.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';

class ImmichTitleText extends StatelessWidget {
  final double fontSize;

  const ImmichTitleText({super.key, this.fontSize = 48});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Isosmart ',
          style: TextStyle(
            fontSize: fontSize * 0.7,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: context.isDarkTheme ? Colors.white : Colors.black87,
          ),
        ),
        Text(
          'Photos',
          style: TextStyle(
            fontSize: fontSize * 0.7,
            fontWeight: FontWeight.w400,
            letterSpacing: -0.5,
            color: context.primaryColor,
          ),
        ),
      ],
    );
  }
}
