import 'package:flutter/material.dart';

void showErrorDialog(BuildContext context, String msg) {
  if (!context.mounted) return;
  final alert = AlertDialog(
    title: const Text("Error"),
    content: Text(msg),
    actions: [
      TextButton(
        child: const Text("OK"),
        onPressed: () {
          Navigator.of(context).pop();
        },
      )
    ],
  );

  showDialog(
    context: context,
    builder: (BuildContext context) {
      return alert;
    },
  );
}
