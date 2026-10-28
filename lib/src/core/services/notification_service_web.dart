import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;
import 'package:flutter/foundation.dart';

/// Веб-специфичная реализация для уведомлений
class WebNotificationHelper {
  static bool _webPermissionRequested = false;

  static Future<void> initialize() async {
    // Проверяем поддержку Web Notifications API
    if (html.window.navigator.permissions != null) {
      try {
        final permission = await html.window.navigator.permissions!
            .query({'name': 'notifications'});
        if (permission.state == 'granted') {
          _webPermissionRequested = true;
        } else if (permission.state == 'prompt') {
          // Разрешение еще не запрошено, запросим при первом уведомлении
        }
      } catch (e) {
        debugPrint('Error checking notification permission: $e');
      }
    }
  }

  static Future<void> showNotification({
    required String title,
    required String body,
  }) async {
    try {
      // Проверяем поддержку Web Notifications API
      if (js.context['Notification'] == null) {
        debugPrint('Web Notifications API not supported');
        return;
      }

      // Запрашиваем разрешение, если еще не запрошено
      if (!_webPermissionRequested) {
        final notificationClass = js.context['Notification'] as js.JsObject;
        final permissionPromise =
            notificationClass.callMethod('requestPermission', []);
        final permission =
            await _promiseToFuture(permissionPromise as js.JsObject);
        _webPermissionRequested = true;
        if (permission != 'granted') {
          debugPrint('Notification permission denied');
          return;
        }
      }

      // Проверяем, что разрешение есть
      final notificationClass = js.context['Notification'] as js.JsObject;
      final currentPermission = notificationClass['permission'];
      if (currentPermission != 'granted') {
        debugPrint('Notification permission not granted');
        return;
      }

      // Показываем уведомление через eval (самый простой способ)
      final escapedTitle = title.replaceAll("'", "\\'").replaceAll('"', '\\"');
      final escapedBody = body.replaceAll("'", "\\'").replaceAll('"', '\\"');
      js.context.callMethod('eval', [
        "new Notification('$escapedTitle', {body: '$escapedBody', icon: '/flutter_app/icons/Icon-192.png'})"
      ]);
    } catch (e) {
      debugPrint('Error showing web notification: $e');
    }
  }

  static Future<String> _promiseToFuture(js.JsObject promise) async {
    final completer = Completer<String>();
    promise.callMethod('then', [
      js.allowInterop((result) {
        completer.complete(result.toString());
      }),
      js.allowInterop((error) {
        completer.completeError(error);
      })
    ]);
    return completer.future;
  }
}








