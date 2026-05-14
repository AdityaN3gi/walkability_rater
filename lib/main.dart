import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const WalkabilityApp());
}

// 1. DATA MODEL  — now stores resolved coords
class WalkabilityAudit {
  final String locationDisplay; // human-readable label shown in UI
  final LatLng? coords; // resolved coordinates (null = unknown)
  final int rating;
  final String note;
  final String? imagePath;

  WalkabilityAudit({
    required this.locationDisplay,
    this.coords,
    required this.rating,
    required this.note,
    this.imagePath,
  });
}

/// Returns stored coords if available, otherwise Bengaluru centre.
LatLng auditCoordinates(WalkabilityAudit audit) =>
    audit.coords ?? const LatLng(12.9716, 77.5946);

bool auditHasRealCoords(WalkabilityAudit audit) => audit.coords != null;

Color ratingColor(int rating) {
  if (rating <= 2) return Colors.red;
  if (rating <= 4) return const Color.fromARGB(255, 223, 210, 26);
  if (rating <= 6) return const Color.fromARGB(255, 120, 68, 20);
  if (rating <= 8) return Colors.green;
  return const Color.fromARGB(255, 19, 186, 195);
}

String ratingCategory(int rating) {
  if (rating <= 2) return 'Hazard';
  if (rating <= 4) return 'Bad';
  if (rating <= 6) return 'Walkable';
  if (rating <= 8) return 'Good';
  return 'Great';
}

/// Geocode a plain-text place name via Nominatim.
/// Returns null if the name cannot be resolved.
Future<LatLng?> geocodeAddress(String query) async {
  try {
    final uri = Uri.parse(
      'https://nominatim.openstreetmap.org/search'
      '?q=${Uri.encodeComponent(query)}&format=json&limit=1',
    );
    final response = await http
        .get(uri, headers: {'User-Agent': 'WalkabilityRaterApp/1.0'})
        .timeout(const Duration(seconds: 6));
    if (response.statusCode == 200) {
      final List data = json.decode(response.body);
      if (data.isNotEmpty) {
        return LatLng(
          double.parse(data[0]['lat'] as String),
          double.parse(data[0]['lon'] as String),
        );
      }
    }
  } catch (_) {}
  return null;
}

/// A single suggestion returned by the Nominatim autocomplete search.
class LocationSuggestion {
  final String displayName;
  final LatLng coords;
  LocationSuggestion({required this.displayName, required this.coords});
}

/// Fetches up to 5 place suggestions from Nominatim for [query].
Future<List<LocationSuggestion>> fetchSuggestions(String query) async {
  if (query.length < 2) return [];
  try {
    final uri = Uri.parse(
      'https://nominatim.openstreetmap.org/search'
      '?q=${Uri.encodeComponent(query)}&format=json&limit=5&addressdetails=0',
    );
    final response = await http
        .get(uri, headers: {'User-Agent': 'WalkabilityRaterApp/1.0'})
        .timeout(const Duration(seconds: 5));
    if (response.statusCode == 200) {
      final List data = json.decode(response.body);
      return data.map((item) {
        // Shorten the display name: take only the first 2–3 comma-separated parts
        final parts = (item['display_name'] as String).split(', ');
        final short = parts.take(3).join(', ');
        return LocationSuggestion(
          displayName: short,
          coords: LatLng(
            double.parse(item['lat'] as String),
            double.parse(item['lon'] as String),
          ),
        );
      }).toList();
    }
  } catch (_) {}
  return [];
}

//  ROOT APP WIDGET
class WalkabilityApp extends StatelessWidget {
  const WalkabilityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Urban Walkability Rater',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color.fromARGB(255, 52, 53, 49),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF121212),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF121212),
          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.grey,
        ),
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          secondary: Colors.grey,
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.grey.shade800),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.grey.shade800),
          ),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white),
          ),
          labelStyle: const TextStyle(color: Colors.grey),
        ),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

// 3. MAIN SCREEN
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final List<WalkabilityAudit> _audits = [];
  String? _pendingMapFilter;

  void _addAudit(WalkabilityAudit audit) {
    setState(() {
      _audits.add(audit);
      _currentIndex = 1;
    });
  }

  void _openMapWithFilter(String filter) {
    setState(() {
      _pendingMapFilter = filter;
      _currentIndex = 2;
    });
  }

  Widget _buildBody() {
    switch (_currentIndex) {
      case 0:
        return AuditForm(onSubmit: _addAudit);
      case 1:
        return Dashboard(audits: _audits, onFilterTap: _openMapWithFilter);
      case 2:
        final filter = _pendingMapFilter ?? 'All';
        _pendingMapFilter = null;
        return MapScreen(audits: _audits, initialFilter: filter);
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Walkability Rater',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: _buildBody(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.edit_document),
            label: 'New Audit',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.pie_chart),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Map'),
        ],
      ),
    );
  }
}

// 4. AUDIT FORM  — geocodes manual text on save
class AuditForm extends StatefulWidget {
  final Function(WalkabilityAudit) onSubmit;
  const AuditForm({super.key, required this.onSubmit});

  @override
  State<AuditForm> createState() => _AuditFormState();
}

class _AuditFormState extends State<AuditForm> {
  double _currentRating = 5;
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  bool _isLocating = false;
  LatLng? _resolvedCoords;
  XFile? _selectedImage;
  final ImagePicker _picker = ImagePicker();

  // Autocomplete state
  List<LocationSuggestion> _suggestions = [];
  bool _loadingSuggestions = false;
  bool _showSuggestions = false;
  Timer? _debounce;

  Future<void> _pickImage(ImageSource source) async {
    final XFile? image = await _picker.pickImage(
      source: source,
      imageQuality: 50,
    );
    if (image != null) setState(() => _selectedImage = image);
  }

  void _onLocationChanged(String value) {
    // Clear any previously resolved coords when user types
    setState(() {
      _resolvedCoords = null;
      _showSuggestions = value.length >= 2;
    });
    _debounce?.cancel();
    if (value.length < 2) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      setState(() => _loadingSuggestions = true);
      final results = await fetchSuggestions(value);
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _loadingSuggestions = false;
        _showSuggestions = true;
      });
    });
  }

  void _selectSuggestion(LocationSuggestion s) {
    _locationController.text = s.displayName;
    setState(() {
      _resolvedCoords = s.coords;
      _suggestions = [];
      _showSuggestions = false;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _locationController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _getGPSLocation() async {
    setState(() => _isLocating = true);
    double lat = 12.9716;
    double lng = 77.5946;
    bool gotReal = false;

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.whileInUse ||
            permission == LocationPermission.always) {
          Position position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 5),
          );
          lat = position.latitude;
          lng = position.longitude;
          gotReal = true;
        }
      }
    } catch (e) {
      final random = Random();
      lat += (random.nextDouble() * 0.05) - 0.025;
      lng += (random.nextDouble() * 0.05) - 0.025;
    }

    setState(() {
      _resolvedCoords = LatLng(lat, lng);
      _locationController.text = gotReal
          ? 'GPS: ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}'
          : 'Approx: ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
      _isLocating = false;
    });
  }

  void _submitAudit() {
    final locationText = _locationController.text.trim().isEmpty
        ? 'Unknown Location'
        : _locationController.text.trim();

    // Warn if the user typed but never picked a suggestion
    if (_resolvedCoords == null &&
        locationText != 'Unknown Location' &&
        !locationText.startsWith('GPS:') &&
        !locationText.startsWith('Approx:')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Please pick a location from the suggestions, or use GPS',
          ),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.orange.shade800,
        ),
      );
      return;
    }

    final newAudit = WalkabilityAudit(
      locationDisplay: locationText,
      coords: _resolvedCoords,
      rating: _currentRating.toInt(),
      note: _noteController.text.isEmpty
          ? 'No description provided'
          : _noteController.text,
      imagePath: _selectedImage?.path,
    );

    widget.onSubmit(newAudit);
    _locationController.clear();
    _noteController.clear();
    setState(() {
      _currentRating = 5;
      _selectedImage = null;
      _resolvedCoords = null;
      _suggestions = [];
      _showSuggestions = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Location',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          // ── LOCATION INPUT + SUGGESTION DROPDOWN ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _locationController,
                      style: const TextStyle(color: Colors.white),
                      onChanged: _onLocationChanged,
                      decoration: InputDecoration(
                        labelText: 'Search a place…',
                        suffixIcon: _loadingSuggestions
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.grey,
                                  ),
                                ),
                              )
                            : _resolvedCoords != null
                            ? const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                                size: 20,
                              )
                            : null,
                      ),
                    ),
                    // Suggestion dropdown
                    if (_showSuggestions && _suggestions.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E1E),
                          border: Border.all(color: Colors.grey.shade800),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: _suggestions.map((s) {
                            return InkWell(
                              onTap: () => _selectSuggestion(s),
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.place_outlined,
                                      color: Colors.grey,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        s.displayName,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    // Nudge if user typed but hasn't picked
                    if (_showSuggestions &&
                        _suggestions.isEmpty &&
                        !_loadingSuggestions &&
                        _locationController.text.length >= 2 &&
                        _resolvedCoords == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'No results — try a different name',
                          style: TextStyle(
                            color: Colors.orange.shade400,
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _isLocating ? null : _getGPSLocation,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isLocating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.black,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.gps_fixed),
              ),
            ],
          ),
          const SizedBox(height: 25),
          const Text(
            'Attach Photo',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Camera'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade900,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Gallery'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade900,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_selectedImage != null) ...[
            const SizedBox(height: 10),
            Container(
              height: 120,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade800),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(_selectedImage!.path),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ],
          const SizedBox(height: 35),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text(
                'Hazard (1)',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Perfect (10)',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 12.0,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 14.0),
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.grey.shade900,
              thumbColor: Colors.white,
              activeTickMarkColor: Colors.black,
              inactiveTickMarkColor: Colors.grey.shade800,
            ),
            child: Slider(
              value: _currentRating,
              min: 1,
              max: 10,
              divisions: 9,
              label: _currentRating.round().toString(),
              onChanged: (value) => setState(() => _currentRating = value),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _noteController,
            maxLines: 2,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(labelText: 'Notes'),
          ),
          const SizedBox(height: 40),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: _isLocating ? null : _submitAudit,
            icon: const Icon(Icons.save),
            label: const Text(
              'Save Audit',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

// DASHBOARD
class Dashboard extends StatefulWidget {
  final List<WalkabilityAudit> audits;
  final void Function(String filter) onFilterTap;

  const Dashboard({super.key, required this.audits, required this.onFilterTap});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  int _touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    final audits = widget.audits;

    if (audits.isEmpty) {
      return const Center(
        child: Text('No data yet.', style: TextStyle(color: Colors.grey)),
      );
    }

    final categories = <String, List<WalkabilityAudit>>{
      'Hazard': audits.where((a) => a.rating <= 2).toList(),
      'Bad': audits.where((a) => a.rating == 3 || a.rating == 4).toList(),
      'Walkable': audits.where((a) => a.rating == 5 || a.rating == 6).toList(),
      'Good': audits.where((a) => a.rating == 7 || a.rating == 8).toList(),
      'Great': audits.where((a) => a.rating >= 9).toList(),
    };

    final categoryColors = <String, Color>{
      'Hazard': Colors.red,
      'Bad': const Color.fromARGB(255, 223, 210, 26),
      'Walkable': const Color.fromARGB(255, 120, 68, 20),
      'Good': Colors.green,
      'Great': const Color.fromARGB(255, 19, 186, 195),
    };

    final activeCategories = categories.entries
        .where((e) => e.value.isNotEmpty)
        .toList();

    return Column(
      children: [
        SizedBox(
          height: 240,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 50,
                  pieTouchData: PieTouchData(
                    touchCallback: (FlTouchEvent event, pieTouchResponse) {
                      setState(() {
                        if (!event.isInterestedForInteractions ||
                            pieTouchResponse == null ||
                            pieTouchResponse.touchedSection == null) {
                          _touchedIndex = -1;
                          return;
                        }
                        _touchedIndex = pieTouchResponse
                            .touchedSection!
                            .touchedSectionIndex;
                      });
                      if (event is FlTapUpEvent &&
                          pieTouchResponse?.touchedSection != null) {
                        final idx = pieTouchResponse!
                            .touchedSection!
                            .touchedSectionIndex;
                        if (idx >= 0 && idx < activeCategories.length) {
                          widget.onFilterTap(activeCategories[idx].key);
                        }
                      }
                    },
                  ),
                  sections: List.generate(activeCategories.length, (i) {
                    final entry = activeCategories[i];
                    final isTouched = i == _touchedIndex;
                    return PieChartSectionData(
                      value: entry.value.length.toDouble(),
                      color: categoryColors[entry.key]!,
                      title: '${entry.value.length}',
                      radius: isTouched ? 62 : 50,
                      titleStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    );
                  }),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.touch_app, color: Colors.grey, size: 16),
                  const SizedBox(height: 2),
                  Text(
                    'tap to\nfilter map',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 12,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: activeCategories.map((entry) {
              return GestureDetector(
                onTap: () => widget.onFilterTap(entry.key),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: categoryColors[entry.key],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      entry.key,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        const Divider(color: Colors.grey),
        Expanded(
          child: ListView.builder(
            itemCount: audits.length,
            itemBuilder: (context, index) {
              final audit = audits[index];
              return ListTile(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AuditDetailScreen(audit: audit),
                  ),
                ),
                leading: CircleAvatar(
                  backgroundColor: ratingColor(audit.rating),
                  child: Text(
                    audit.rating.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(
                  audit.note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  audit.locationDisplay,
                  style: const TextStyle(color: Colors.grey),
                ),
                trailing: audit.imagePath != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.file(
                          File(audit.imagePath!),
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                        ),
                      )
                    : const Icon(Icons.image_not_supported, color: Colors.grey),
              );
            },
          ),
        ),
      ],
    );
  }
}

//  MAP SCREEN

class MapScreen extends StatefulWidget {
  final List<WalkabilityAudit> audits;
  final String initialFilter;

  const MapScreen({
    super.key,
    required this.audits,
    this.initialFilter = 'All',
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late String _activeFilter;

  static const _filters = ['All', 'Hazard', 'Bad', 'Walkable', 'Good', 'Great'];
  static const _filterColors = <String, Color>{
    'All': Colors.white,
    'Hazard': Colors.red,
    'Bad': Color.fromARGB(255, 223, 210, 26),
    'Walkable': Color.fromARGB(255, 120, 68, 20),
    'Good': Colors.green,
    'Great': Color.fromARGB(255, 19, 186, 195),
  };

  @override
  void initState() {
    super.initState();
    _activeFilter = widget.initialFilter;
  }

  @override
  void didUpdateWidget(MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialFilter != widget.initialFilter) {
      setState(() => _activeFilter = widget.initialFilter);
    }
  }

  List<WalkabilityAudit> get _filteredAudits {
    if (_activeFilter == 'All') return widget.audits;
    return widget.audits
        .where((a) => ratingCategory(a.rating) == _activeFilter)
        .toList();
  }

  LatLng get _mapCenter {
    final filtered = _filteredAudits;
    if (filtered.isEmpty) return const LatLng(12.9716, 77.5946);
    double lat = 0, lng = 0;
    for (final a in filtered) {
      final c = auditCoordinates(a);
      lat += c.latitude;
      lng += c.longitude;
    }
    return LatLng(lat / filtered.length, lng / filtered.length);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredAudits;

    return Column(
      children: [
        // Filter chips
        Container(
          color: const Color(0xFF121212),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _filters.map((f) {
                final isActive = f == _activeFilter;
                final chipColor = _filterColors[f]!;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilterChip(
                    label: Text(f),
                    selected: isActive,
                    onSelected: (_) => setState(() => _activeFilter = f),
                    backgroundColor: Colors.grey.shade900,
                    selectedColor: chipColor.withOpacity(0.25),
                    checkmarkColor: chipColor,
                    labelStyle: TextStyle(
                      color: isActive ? chipColor : Colors.grey,
                      fontWeight: isActive
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                    side: BorderSide(
                      color: isActive ? chipColor : Colors.grey.shade800,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        // Map
        Expanded(
          child: widget.audits.isEmpty
              ? const Center(
                  child: Text(
                    'No audits yet.\nSave an audit to see it on the map.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : FlutterMap(
                  key: ValueKey(_activeFilter),
                  options: MapOptions(
                    initialCenter: _mapCenter,
                    initialZoom: 14.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.walkability_rater',
                    ),
                    MarkerLayer(
                      markers: filtered.map((audit) {
                        final pos = auditCoordinates(audit);
                        final color = ratingColor(audit.rating);
                        return Marker(
                          point: pos,
                          width: 60,
                          height: 60,
                          child: GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AuditDetailScreen(audit: audit),
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: color.withOpacity(0.5),
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    audit.rating.toString(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 10,
                                  height: 8,
                                  child: _TriangleWidget(color: color),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
        ),

        // Count bar
        if (widget.audits.isNotEmpty)
          Container(
            color: const Color(0xFF121212),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.place,
                  size: 14,
                  color: _filterColors[_activeFilter]!,
                ),
                const SizedBox(width: 6),
                Text(
                  '${filtered.length} '
                  '${filtered.length == 1 ? 'location' : 'locations'}'
                  '${_activeFilter == 'All' ? '' : ' · $_activeFilter'}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// PIN TAIL WIDGET
class _TriangleWidget extends StatelessWidget {
  final Color color;
  const _TriangleWidget({required this.color});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _TrianglePainter(color));
}

class _TrianglePainter extends CustomPainter {
  final Color color;
  _TrianglePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final p = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(p, paint);
  }

  @override
  bool shouldRepaint(_TrianglePainter old) => old.color != color;
}

// AUDIT DETAIL SCREEN — fluid collapsing map
class AuditDetailScreen extends StatelessWidget {
  final WalkabilityAudit audit;
  const AuditDetailScreen({super.key, required this.audit});

  @override
  Widget build(BuildContext context) {
    final position = auditCoordinates(audit);
    final color = ratingColor(audit.rating);
    final hasRealCoords = auditHasRealCoords(audit);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      // No appBar here — the SliverAppBar inside replaces it
      body: CustomScrollView(
        slivers: [
          // ── COLLAPSING MAP HEADER ──
          SliverAppBar(
            backgroundColor: const Color(0xFF121212),
            foregroundColor: Colors.white,
            expandedHeight: 320,
            pinned: true, // keeps the bar visible when collapsed
            snap: false,
            floating: false,
            flexibleSpace: FlexibleSpaceBar(
              // Title shown when collapsed
              title: Text(
                audit.locationDisplay,
                style: const TextStyle(fontSize: 13, color: Colors.white),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              // The map fills the expanded area
              background: Stack(
                children: [
                  FlutterMap(
                    options: MapOptions(
                      initialCenter: position,
                      initialZoom: 15.0,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.walkability_rater',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: position,
                            width: 80,
                            height: 80,
                            child: Icon(
                              Icons.location_on,
                              color: color,
                              size: 40,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  // Warning banner if coords were not resolved
                  if (!hasRealCoords)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        color: Colors.black54,
                        padding: const EdgeInsets.symmetric(
                          vertical: 6,
                          horizontal: 12,
                        ),
                        child: Row(
                          children: const [
                            Icon(
                              Icons.info_outline,
                              color: Colors.orangeAccent,
                              size: 14,
                            ),
                            SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Exact location unknown — showing city centre',
                                style: TextStyle(
                                  color: Colors.orangeAccent,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── SCROLLABLE CONTENT ──
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Optional photo
                if (audit.imagePath != null)
                  Image.file(
                    File(audit.imagePath!),
                    height: 220,
                    fit: BoxFit.cover,
                  ),

                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        audit.locationDisplay,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Rating: ${audit.rating}/10  ·  ${ratingCategory(audit.rating)}',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Divider(height: 40, color: Colors.grey),
                      const Text(
                        'NOTES',
                        style: TextStyle(
                          color: Colors.grey,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        audit.note,
                        style: const TextStyle(
                          fontSize: 18,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
