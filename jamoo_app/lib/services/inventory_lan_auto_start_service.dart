import 'dart:async';

import 'inventory_lan_server_service.dart';

/// Keeps the mobile inventory/reservation server available while the app runs.
class InventoryLanAutoStartService {
  InventoryLanAutoStartService._();

  static final InventoryLanAutoStartService instance =
      InventoryLanAutoStartService._();

  Timer? _watchdog;
  bool _starting = false;

  void start({String facilityName = 'JamooManager'}) {
    if (_watchdog != null) return;
    unawaited(_ensureRunning(facilityName));
    _watchdog = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_ensureRunning(facilityName)),
    );
  }

  Future<void> _ensureRunning(String facilityName) async {
    if (_starting || InventoryLanServerService.instance.isRunning) return;
    _starting = true;
    try {
      await InventoryLanServerService.instance.start(
        facilityName: facilityName,
      );
    } catch (_) {
      // A temporary network/port failure is retried by the watchdog.
    } finally {
      _starting = false;
    }
  }
}
