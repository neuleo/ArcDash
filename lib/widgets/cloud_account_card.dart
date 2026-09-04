import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/providers/cloud_sync_provider.dart';

class CloudAccountCard extends ConsumerWidget {
  const CloudAccountCard({super.key});

  void _showAuthDialog(BuildContext context, {bool isRegister = false}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0D1117),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AuthModal(initialIsRegister: isRegister),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(cloudSyncProvider);
    final syncNotifier = ref.read(cloudSyncProvider.notifier);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111518),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: syncState.isAuthenticated
              ? const Color(0xFF54E39E).withOpacity(0.4)
              : const Color(0xFF00E5FF).withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (syncState.isAuthenticated
                          ? const Color(0xFF54E39E)
                          : const Color(0xFF00E5FF))
                      .withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  syncState.isAuthenticated
                      ? Icons.cloud_done
                      : Icons.cloud_queue,
                  color: syncState.isAuthenticated
                      ? const Color(0xFF54E39E)
                      : const Color(0xFF00E5FF),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      syncState.isAuthenticated
                          ? 'CLOUD-SYNC AKTIV'
                          : 'MULTI-DEVICE CLOUD SYNC',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      syncState.isAuthenticated
                          ? 'Angemeldet als: ${syncState.config.username}'
                          : 'Bikes, Tuning-Profile & Fahrten geräteübergreifend syncen',
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (syncState.isAuthenticated) ...[
            // Logged in UI: Last Sync + Sync Now + Logout
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        syncState.lastSyncTime != null
                            ? 'Zuletzt: ${syncState.lastSyncTime!.hour.toString().padLeft(2, "0")}:${syncState.lastSyncTime!.minute.toString().padLeft(2, "0")} Uhr'
                            : 'Noch nicht synchronisiert',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                      Text(
                        'Server: ${syncState.config.serverUrl}',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 10),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF123328),
                    foregroundColor: const Color(0xFF54E39E),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed:
                      syncState.isSyncing ? null : () => syncNotifier.syncNow(),
                  icon: syncState.isSyncing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Color(0xFF54E39E)),
                        )
                      : const Icon(Icons.sync, size: 16),
                  label: Text(
                    syncState.isSyncing ? 'SYNC...' : 'SYNC JETZT',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Abmelden',
                  icon:
                      const Icon(Icons.logout, color: Colors.white38, size: 18),
                  onPressed: () => syncNotifier.logout(),
                ),
              ],
            ),
          ] else ...[
            // Logged out UI: Login / Register Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF00E5FF),
                      side: const BorderSide(color: Color(0xFF00E5FF)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () =>
                        _showAuthDialog(context, isRegister: false),
                    child: const Text('ANMELDEN',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5FF),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _showAuthDialog(context, isRegister: true),
                    child: const Text('REGISTRIEREN',
                        style: TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 12)),
                  ),
                ),
              ],
            ),
          ],
          if (syncState.statusMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              syncState.statusMessage!,
              style: const TextStyle(
                  color: Color(0xFF54E39E),
                  fontSize: 11,
                  fontWeight: FontWeight.bold),
            ),
          ],
          if (syncState.lastError != null) ...[
            const SizedBox(height: 8),
            Text(
              syncState.lastError!,
              style: const TextStyle(
                  color: Color(0xFFFF5252),
                  fontSize: 11,
                  fontWeight: FontWeight.bold),
            ),
          ],
        ],
      ),
    );
  }
}

class _AuthModal extends ConsumerStatefulWidget {
  final bool initialIsRegister;
  const _AuthModal({required this.initialIsRegister});

  @override
  ConsumerState<_AuthModal> createState() => _AuthModalState();
}

class _AuthModalState extends ConsumerState<_AuthModal> {
  late bool _isRegister;
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _serverUrlCtrl = TextEditingController(text: 'http://172.24.1.1:8080');

  @override
  void initState() {
    super.initState();
    _isRegister = widget.initialIsRegister;
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    _emailCtrl.dispose();
    _serverUrlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final syncState = ref.watch(cloudSyncProvider);
    final syncNotifier = ref.read(cloudSyncProvider.notifier);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _isRegister ? 'KONTO ERSTELLEN' : 'IN CLOUD ANMELDEN',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  letterSpacing: 1.2,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _userCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Benutzername',
              labelStyle: const TextStyle(color: Colors.white54, fontSize: 13),
              filled: true,
              fillColor: const Color(0xFF161B22),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _passCtrl,
            obscureText: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Passwort',
              labelStyle: const TextStyle(color: Colors.white54, fontSize: 13),
              filled: true,
              fillColor: const Color(0xFF161B22),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 10),
          if (_isRegister) ...[
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'E-Mail (Optional)',
                labelStyle:
                    const TextStyle(color: Colors.white54, fontSize: 13),
                filled: true,
                fillColor: const Color(0xFF161B22),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: _serverUrlCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: InputDecoration(
              labelText: 'Server-URL (Standard: Docker Host)',
              labelStyle: const TextStyle(color: Colors.white54, fontSize: 11),
              filled: true,
              fillColor: const Color(0xFF161B22),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E5FF),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: syncState.isSyncing
                ? null
                : () async {
                    final u = _userCtrl.text.trim();
                    final p = _passCtrl.text.trim();
                    final s = _serverUrlCtrl.text.trim();
                    final em = _emailCtrl.text.trim();

                    if (u.isEmpty || p.isEmpty) return;

                    final bool ok;
                    if (_isRegister) {
                      ok = await syncNotifier.register(
                        username: u,
                        password: p,
                        email: em.isNotEmpty ? em : null,
                        serverUrl: s.isNotEmpty ? s : null,
                      );
                    } else {
                      ok = await syncNotifier.login(
                        username: u,
                        password: p,
                        serverUrl: s.isNotEmpty ? s : null,
                      );
                    }

                    if (ok && mounted) {
                      Navigator.pop(context);
                    }
                  },
            child: Text(
              syncState.isSyncing
                  ? 'BITTE WARTEN...'
                  : (_isRegister
                      ? 'REGISTRIEREN & SYNC STARTEN'
                      : 'ANMELDEN & SYNC STARTEN'),
              style: const TextStyle(
                  fontWeight: FontWeight.w900, letterSpacing: 1),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => setState(() => _isRegister = !_isRegister),
            child: Text(
              _isRegister
                  ? 'Bereits ein Konto? Hier anmelden'
                  : 'Noch kein Konto? Hier registrieren',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
