import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  runApp(const ErrApp());
}

class ErrApp extends StatelessWidget {
  const ErrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Err',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
      ),
      home: const LocationScreen(),
    );
  }
}

class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key});

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  Position? _position;
  String? _error;
  bool _loading = false;

  Future<void> _fetchLocation() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() {
          _error = 'Location permission denied.';
          _loading = false;
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      setState(() {
        _position = position;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not get location: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Err'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_position != null) ...[
                _LocationTile('Latitude', _position!.latitude.toStringAsFixed(6)),
                _LocationTile('Longitude', _position!.longitude.toStringAsFixed(6)),
                _LocationTile('Altitude', '${_position!.altitude.toStringAsFixed(1)} m'),
                _LocationTile('Speed', '${(_position!.speed * 3.6).toStringAsFixed(1)} km/h'),
                _LocationTile('Accuracy', '±${_position!.accuracy.toStringAsFixed(0)} m'),
                const SizedBox(height: 32),
              ] else if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 32),
              ] else if (!_loading) ...[
                const Text('Tap the button to get your location.'),
                const SizedBox(height: 32),
              ],
              if (_loading)
                const CircularProgressIndicator()
              else
                ElevatedButton.icon(
                  onPressed: _fetchLocation,
                  icon: const Icon(Icons.my_location),
                  label: Text(_position == null ? 'Get My Location' : 'Refresh'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationTile extends StatelessWidget {
  const _LocationTile(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(value),
        ],
      ),
    );
  }
}
