// Показ кода восстановления PIN (один раз). Хозяин должен записать или сфотографировать его.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> showRecoveryCode(BuildContext context, String code) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      title: Text('Код восстановления PIN'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Если хозяин забудет PIN, этим кодом можно задать новый. '
            'Запишите его или сфотографируйте и храните в надёжном месте. '
            'Больше он показан не будет.'),
        SizedBox(height: 16),
        Center(
          child: SelectableText(code,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 2)),
        ),
      ]),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: code));
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Код скопирован')));
          },
          child: Text('Копировать'),
        ),
        FilledButton(onPressed: () => Navigator.pop(c), child: Text('Я записал код')),
      ],
    ),
  );
}
