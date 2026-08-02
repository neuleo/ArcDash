import 'package:permission_handler/permission_handler.dart' as handler;

enum RuntimePermission {
  bluetoothScan,
  bluetoothConnect,
  location,
}

class AndroidPermissionPolicy {
  static Set<RuntimePermission> requiredForSdk(int sdk) {
    if (sdk >= 31) {
      return {
        RuntimePermission.bluetoothScan,
        RuntimePermission.bluetoothConnect,
      };
    }
    return {RuntimePermission.location};
  }
}

abstract interface class PermissionRequester {
  Future<bool> request(RuntimePermission permission);
}

class PermissionRequestResult {
  final Set<RuntimePermission> requested;
  final Set<RuntimePermission> denied;

  const PermissionRequestResult({
    required this.requested,
    required this.denied,
  });

  bool get granted => denied.isEmpty;
}

class AndroidPermissionService {
  final PermissionRequester _requester;

  const AndroidPermissionService(this._requester);

  Future<PermissionRequestResult> requestForSdk(int sdk) async {
    final required = AndroidPermissionPolicy.requiredForSdk(sdk);
    final denied = <RuntimePermission>{};
    for (final permission in required) {
      if (!await _requester.request(permission)) denied.add(permission);
    }
    return PermissionRequestResult(
      requested: Set.unmodifiable(required),
      denied: Set.unmodifiable(denied),
    );
  }
}

class PermissionHandlerRequester implements PermissionRequester {
  const PermissionHandlerRequester();

  @override
  Future<bool> request(RuntimePermission permission) async {
    final status = await switch (permission) {
      RuntimePermission.bluetoothScan =>
        handler.Permission.bluetoothScan.request(),
      RuntimePermission.bluetoothConnect =>
        handler.Permission.bluetoothConnect.request(),
      RuntimePermission.location =>
        handler.Permission.locationWhenInUse.request(),
    };
    return status.isGranted;
  }
}
