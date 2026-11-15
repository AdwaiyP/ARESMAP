import 'package:flutter/material.dart' hide DataRow;

import '../theme/ares_theme.dart';
import '../util/space_edac.dart';
import 'hud.dart';

class EdacDialog extends StatefulWidget {
  const EdacDialog({super.key});
  @override
  State<EdacDialog> createState() => _EdacDialogState();
}

class _EdacDialogState extends State<EdacDialog> {
  final _payload = TextEditingController(
    text: 'ARES | EVA-1 | WAYPOINT 137.4000,-4.6550',
  );
  bool _double = false;
  int _flips = 1;
  EdacResult? _result;
  @override
  void dispose() {
    _payload.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Space-link integrity test'),
    content: SizedBox(
      width: 570,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Local fault injection · no radio transmission',
              style: AresType.monoStyle(size: 12, color: AresColors.amber),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _payload,
              maxLength: 256,
              decoration: const InputDecoration(labelText: 'Test packet'),
              onChanged: (_) => setState(() => _result = null),
            ),
            Row(
              children: [
                const Text('Corrupted codewords'),
                Expanded(
                  child: Slider(
                    value: _flips.toDouble(),
                    min: 0,
                    max: 8,
                    divisions: 8,
                    label: '$_flips',
                    onChanged: (v) => setState(() {
                      _flips = v.round();
                      _result = null;
                    }),
                  ),
                ),
                Text('$_flips'),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Two bit flips per codeword'),
              subtitle: const Text('Beyond Hamming(7,4) correction capability'),
              value: _double,
              onChanged: (v) => setState(() {
                _double = v;
                _result = null;
              }),
            ),
            const SizedBox(height: 12),
            AresButton(
              label: 'Run bit-flip test',
              icon: Icons.science_outlined,
              expanded: true,
              onTap: _payload.text.isEmpty
                  ? null
                  : () => setState(
                      () => _result = testSpaceLink(
                        _payload.text,
                        flips: _flips,
                        doubleError: _double,
                      ),
                    ),
            ),
            if (_result != null) ...[
              const SizedBox(height: 20),
              Text(
                _result!.verified
                    ? 'CRC verified · packet recovered'
                    : 'CRC mismatch · reject packet',
                style: AresType.displayStyle(
                  size: 24,
                  color: _result!.verified ? AresColors.green : AresColors.red,
                ),
              ),
              const SizedBox(height: 10),
              DataRow(label: 'Injected bit flips', value: '${_result!.flips}'),
              DataRow(
                label: 'Correction attempts',
                value: '${_result!.correctedWords}',
              ),
              DataRow(label: 'Transmit CRC32', value: _result!.txCrc),
              DataRow(label: 'Recovered CRC32', value: _result!.rxCrc),
              const SizedBox(height: 10),
              SelectableText(
                _result!.received,
                style: AresType.monoStyle(size: 12),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Hamming(7,4) corrects one flipped bit per codeword. CRC32 checks accidental corruption; it is not authentication.',
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}
