import 'package:flutter/material.dart';

import 'data/ares_dataset.dart';
import 'data/backend_api.dart';
import 'screens/ares_map_workspace.dart';
import 'state/ares_scope.dart';
import 'state/ares_state.dart';
import 'theme/ares_theme.dart';
import 'widgets/hud.dart';

class AresBootstrap extends StatefulWidget {
  const AresBootstrap({super.key});

  @override
  State<AresBootstrap> createState() => _AresBootstrapState();
}

class _AresBootstrapState extends State<AresBootstrap> {
  AresState? _state;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await AresDataset.load();
      if (!mounted) return;
      setState(() {
        _state = AresState(data, backend: AresBackend());
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _state?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_state != null) {
      return AresScope(state: _state!, child: const AresAppShell());
    }
    if (_error != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAresTheme(),
        home: _BootScreen(
          error: '$_error',
          onRetry: _loading ? null : _load,
          loading: _loading,
        ),
      );
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAresTheme(),
      home: const _BootScreen(),
    );
  }
}

class AresAppShell extends StatelessWidget {
  const AresAppShell({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ARES MAP — Mars EVA Tactical GIS & 3D Surface Simulation',
      debugShowCheckedModeBanner: false,
      theme: buildAresTheme(),
      home: const AresMapWorkspace(),
    );
  }
}

class _BootScreen extends StatelessWidget {
  const _BootScreen({this.error, this.onRetry, this.loading = true});

  final String? error;
  final VoidCallback? onRetry;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF09090B),
      body: Center(
        child: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AresColors.cyan.withValues(alpha: 0.45),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AresColors.cyan.withValues(alpha: 0.12),
                      blurRadius: 32,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.public,
                  size: 34,
                  color: AresColors.cyan,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'ARES MAP',
                style: AresType.displayStyle(
                  size: 40,
                  spacing: 6,
                  color: AresColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'MARS EVA TACTICAL MAP · GALE & JEZERO',
                style: AresType.label(
                  size: 9,
                  color: AresColors.muted,
                  spacing: 2.2,
                ),
              ),
              const SizedBox(height: 30),
              if (error == null) ...[
                const SizedBox(
                  height: 2,
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    color: AresColors.cyan,
                    backgroundColor: AresColors.line,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'LOADING ARCHIVE · 730 THEMIS STAMPS · 63 MEDA BUCKETS',
                  textAlign: TextAlign.center,
                  style: AresType.monoStyle(size: 8.5, color: AresColors.dim),
                ),
              ] else ...[
                Text(
                  'ARCHIVE LOAD FAILED',
                  style: AresType.label(
                    size: 11,
                    color: AresColors.red,
                    spacing: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  error!,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AresType.monoStyle(size: 9, color: AresColors.muted),
                ),
                const SizedBox(height: 16),
                AresButton(
                  label: loading ? 'Retrying' : 'Retry archive load',
                  icon: Icons.refresh,
                  onTap: onRetry,
                ),
              ],
              const SizedBox(height: 26),
              Text(
                'NASA SPACE APPS CHALLENGE 2026 · TEAM ARES',
                style: AresType.label(
                  size: 7.5,
                  color: AresColors.dim,
                  spacing: 1.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
