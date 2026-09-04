import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/models/bike_profile.dart';
import 'package:arcdash/providers/bike_selector_provider.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/services/ant_bms_service.dart';
import 'package:arcdash/services/bluetooth_service.dart';

/// BottomSheet / Dialog allowing the user to create, edit, or delete a BikeProfile.
class BikeEditModal extends ConsumerStatefulWidget {
  final BikeProfile? initialBike;

  const BikeEditModal({super.key, this.initialBike});

  @override
  ConsumerState<BikeEditModal> createState() => _BikeEditModalState();
}

class _BikeEditModalState extends ConsumerState<BikeEditModal> {
  late TextEditingController _nameCtrl;
  String? _selectedControllerId;
  String _selectedControllerName = 'FarDriver Controller';
  String? _selectedBmsId;
  String _selectedBmsName = 'ANT BMS';

  @override
  void initState() {
    super.initState();
    final b = widget.initialBike;
    _nameCtrl = TextEditingController(text: b?.name ?? '');
    _selectedControllerId =
        b != null && b.controllerId.isNotEmpty ? b.controllerId : null;
    _selectedControllerName = b?.controllerName ?? 'FarDriver Controller';
    _selectedBmsId = b != null && b.bmsId.isNotEmpty ? b.bmsId : null;
    _selectedBmsName = b?.bmsName ?? 'ANT BMS';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scanResults = ref.watch(scanResultsProvider).valueOrNull ?? [];
    final isEditing = widget.initialBike != null;

    // Filter potential controllers and BMS devices from scan results or remembered
    final controllerCandidates = <_DeviceChoice>[];
    final bmsCandidates = <_DeviceChoice>[];

    for (final d in scanResults) {
      final isBms = isAntBmsName(d.name, d.device.remoteId.str);
      final choice = _DeviceChoice(
        id: d.device.remoteId.str,
        name: d.name.isNotEmpty ? d.name : (isBms ? 'ANT BMS' : 'FarDriver'),
      );
      if (isBms) {
        if (!bmsCandidates.any((c) => c.id == choice.id))
          bmsCandidates.add(choice);
      } else {
        if (!controllerCandidates.any((c) => c.id == choice.id))
          controllerCandidates.add(choice);
      }
    }

    // Ensure currently selected devices are present in dropdown choices
    if (_selectedControllerId != null &&
        !controllerCandidates.any((c) => c.id == _selectedControllerId)) {
      controllerCandidates.add(_DeviceChoice(
        id: _selectedControllerId!,
        name: _selectedControllerName,
      ));
    }

    if (_selectedBmsId != null &&
        !bmsCandidates.any((c) => c.id == _selectedBmsId)) {
      bmsCandidates.add(_DeviceChoice(
        id: _selectedBmsId!,
        name: _selectedBmsName,
      ));
    }

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
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E5FF).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.two_wheeler,
                        color: Color(0xFF00E5FF), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isEditing ? 'BIKE BEARBEITEN' : 'NEUES BIKE ANLEGEN',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Bike Name field
          TextField(
            controller: _nameCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Bike-Name (z.B. Mein Arctic Leopard, Bike Frau)',
              labelStyle: const TextStyle(color: Colors.white54, fontSize: 13),
              filled: true,
              fillColor: const Color(0xFF161B22),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Controller Selection
          const Text('Zugeordneter Motor-Controller:',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedControllerId,
                hint: const Text('Controller auswählen...',
                    style: TextStyle(color: Colors.white38)),
                isExpanded: true,
                dropdownColor: const Color(0xFF161B22),
                style: const TextStyle(color: Colors.white, fontSize: 14),
                items: [
                  for (final c in controllerCandidates)
                    DropdownMenuItem(
                      value: c.id,
                      child: Text(
                          '${c.name} (${c.id.length > 10 ? "${c.id.substring(0, 8)}..." : c.id})'),
                    ),
                ],
                onChanged: (val) {
                  setState(() {
                    _selectedControllerId = val;
                    final match = controllerCandidates.firstWhere(
                        (c) => c.id == val,
                        orElse: () =>
                            _DeviceChoice(id: val ?? '', name: 'Controller'));
                    _selectedControllerName = match.name;
                  });
                },
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Battery BMS Selection
          const Text('Zugeordnetes Batterie BMS (ANT):',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedBmsId,
                hint: const Text('Kein BMS (Optional)',
                    style: TextStyle(color: Colors.white38)),
                isExpanded: true,
                dropdownColor: const Color(0xFF161B22),
                style: const TextStyle(color: Colors.white, fontSize: 14),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Kein BMS zugewiesen',
                        style: TextStyle(color: Colors.white54)),
                  ),
                  for (final b in bmsCandidates)
                    DropdownMenuItem(
                      value: b.id,
                      child: Text(
                          '${b.name} (${b.id.length > 10 ? "${b.id.substring(0, 8)}..." : b.id})'),
                    ),
                ],
                onChanged: (val) {
                  setState(() {
                    _selectedBmsId = val;
                    if (val != null) {
                      final match = bmsCandidates.firstWhere((b) => b.id == val,
                          orElse: () =>
                              _DeviceChoice(id: val, name: 'ANT BMS'));
                      _selectedBmsName = match.name;
                    }
                  });
                },
              ),
            ),
          ),

          const SizedBox(height: 22),

          // Save / Create Button
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E5FF),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              final name = _nameCtrl.text.trim().isNotEmpty
                  ? _nameCtrl.text.trim()
                  : 'Mein E-Bike';
              final bike = BikeProfile(
                id: widget.initialBike?.id ??
                    'bike_${DateTime.now().millisecondsSinceEpoch}',
                name: name,
                controllerId: _selectedControllerId ?? '',
                controllerName: _selectedControllerName,
                bmsId: _selectedBmsId ?? '',
                bmsName: _selectedBmsName,
                createdAt: widget.initialBike?.createdAt ?? DateTime.now(),
              );
              ref.read(bikeSelectorProvider.notifier).saveBike(bike);
              Navigator.pop(context);
            },
            child: Text(
              isEditing ? 'ÄNDERUNGEN SPEICHERN' : 'BIKE HINZUFÜGEN',
              style: const TextStyle(
                  fontWeight: FontWeight.w900, letterSpacing: 1),
            ),
          ),

          if (isEditing) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Bike löschen',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () {
                ref
                    .read(bikeSelectorProvider.notifier)
                    .deleteBike(widget.initialBike!.id);
                Navigator.pop(context);
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _DeviceChoice {
  final String id;
  final String name;
  const _DeviceChoice({required this.id, required this.name});
}
