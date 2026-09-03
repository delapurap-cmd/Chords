import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Pide permiso de micrófono. Si está denegado para siempre, ofrece ir a
/// Ajustes en vez de insistir con un diálogo del sistema que ya no aparece.
Future<bool> pedirPermisoMic(BuildContext context) async {
  var estado = await Permission.microphone.status;
  if (estado.isGranted) return true;

  if (!estado.isPermanentlyDenied) {
    estado = await Permission.microphone.request();
  }
  if (estado.isGranted) return true;

  if (context.mounted) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permiso de micrófono'),
        content: const Text(
          'Esta app necesita el micrófono para escuchar lo que tocás.\n\n'
          'Activalo en Ajustes → Chords → Micrófono.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await openAppSettings();
            },
            child: const Text('Abrir ajustes'),
          ),
        ],
      ),
    );
  }
  return false;
}
