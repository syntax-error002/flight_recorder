import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flight_blackbox/flight_blackbox.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Flight Recorder at app launch
  FlightRecorder.instance.start(
    config: FlightConfig(
      bufferCapacity: 500,
      moveSampleDistance: 3.0,
      enablePointerRecording: true,
      enableNavigationRecording: true,
      enableLifecycleRecording: true,
      enableHttpRecording: true,
      enableCrashRecording: true,
    ),
  );

  runApp(const FlightRecorderDemoApp());
}

class FlightRecorderDemoApp extends StatelessWidget {
  const FlightRecorderDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flight Recorder Showcase',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      navigatorObservers: [
        FlightRecorder.instance.navigatorObserver,
      ],
      builder: (context, child) {
        // Wrap entire UI with FlightRecorderOverlay for instant diagnostics
        return FlightRecorderOverlay(
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const ProductCatalogScreen(),
    );
  }
}

class ProductCatalogScreen extends StatefulWidget {
  const ProductCatalogScreen({super.key});

  @override
  State<ProductCatalogScreen> createState() => _ProductCatalogScreenState();
}

class _ProductCatalogScreenState extends State<ProductCatalogScreen> {
  final List<String> _cart = [];
  bool _isLoading = false;
  String _networkStatus = 'Ready';

  final List<Map<String, dynamic>> _products = const [
    {'id': '1', 'name': 'MacBook Pro M3 Max', 'price': 3499},
    {'id': '2', 'name': 'Sony WH-1000XM5', 'price': 399},
    {'id': '3', 'name': 'Mechanical Keychron Q1', 'price': 199},
    {'id': '4', 'name': 'Dell UltraSharp 32" 4K', 'price': 899},
  ];

  Future<void> _fetchNetworkStatus() async {
    setState(() {
      _isLoading = true;
      _networkStatus = 'Fetching...';
    });

    try {
      FlightRecorder.instance.addBreadcrumb('API Request Started', category: 'network');
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse('https://httpbin.org/get'));
      final response = await request.close();
      final body = await utf8.decodeStream(response);
      client.close();

      setState(() {
        _isLoading = false;
        _networkStatus = 'HTTP ${response.statusCode} (Length: ${body.length})';
      });
      FlightRecorder.instance.addBreadcrumb('API Request Succeeded', category: 'network');
    } catch (e) {
      setState(() {
        _isLoading = false;
        _networkStatus = 'Error: $e';
      });
    }
  }

  void _triggerSimulatedCrash() {
    FlightRecorder.instance.addBreadcrumb(
      'Triggering Crash Simulation',
      category: 'chaos',
    );
    // Simulate unhandled race condition
    Future.delayed(const Duration(milliseconds: 100), () {
      throw StateError(
        'Simulated NullPointerException: Cart state desynchronized during checkout navigation!',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flight Shop'),
        actions: [
          IconButton(
            icon: Badge(
              label: Text('${_cart.length}'),
              child: const Icon(Icons.shopping_cart),
            ),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => CartScreen(cartItems: _cart),
                  settings: const RouteSettings(name: '/cart'),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.deepPurple.withAlpha(40),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.deepPurpleAccent.withAlpha(80)),
            ),
            child: Row(
              children: [
                const Icon(Icons.flight_takeoff, color: Colors.cyanAccent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Flight Recorder Active',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Tap the red floating button anytime to export .flightlog or synthesize Dart testWidgets!',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _fetchNetworkStatus,
                    icon: const Icon(Icons.cloud_download, size: 18),
                    label: Text(_isLoading ? 'Fetching...' : 'Test HTTP Call'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade900,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _triggerSimulatedCrash,
                    icon: const Icon(Icons.warning, size: 18),
                    label: const Text('Simulate Crash'),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'Network Status: $_networkStatus',
              style: const TextStyle(fontSize: 12, color: Colors.cyanAccent),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: TextField(
              key: const Key('catalog_search_field'),
              decoration: InputDecoration(
                hintText: 'Search products (tests IME recording)...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (val) {
                FlightRecorder.instance.addBreadcrumb(
                  'Search Query Changed',
                  data: {'query': val},
                );
              },
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: _products.length,
              itemBuilder: (context, index) {
                final product = _products[index];
                return ListTile(
                  leading: CircleAvatar(
                    child: Text('${index + 1}'),
                  ),
                  title: Text(product['name'] as String),
                  subtitle: Text('\$${product['price']}'),
                  trailing: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _cart.add(product['name'] as String);
                      });
                      FlightRecorder.instance.addBreadcrumb(
                        'Item Added to Cart',
                        data: {'product': product['name']},
                      );
                    },
                    child: const Text('Add'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class CartScreen extends StatelessWidget {
  final List<String> cartItems;

  const CartScreen({super.key, required this.cartItems});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your Cart')),
      body: cartItems.isEmpty
          ? const Center(child: Text('Your cart is empty'))
          : ListView.builder(
              itemCount: cartItems.length,
              itemBuilder: (context, index) {
                return ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: Text(cartItems[index]),
                );
              },
            ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('coupon_code_field'),
              decoration: const InputDecoration(
                labelText: 'Promo / Secret Code (Redacted in logs)',
                prefixIcon: Icon(Icons.discount),
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                key: const Key('checkout_button'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: () {
                  FlightRecorder.instance.addBreadcrumb(
                    'Checkout Completed',
                    category: 'conversion',
                    data: {'itemCount': cartItems.length},
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Order placed successfully!')),
                  );
                  Navigator.pop(context);
                },
                child: const Text('Checkout & Pay', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
