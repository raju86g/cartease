import 'dart:typed_data';
import 'package:flutter/material.dart';
// import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:cartease/scanner.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math';
import 'dart:ui' as ui;
import 'dart:convert'; // For utf8 encoding
import 'package:crypto/crypto.dart'; // For password hashing
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// Import the generated file
import 'package:image_picker/image_picker.dart';
import 'image_uploader.dart';
import 'firebase_options.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ); // Ensure Firebase is initialized with options
    print('Firebase initialized successfully');
  } catch (e) {
    print('Firebase initialization failed: $e');
    // You might want to show an error screen or fallback here
  }
  await Hive.initFlutter(); // Hive needs to be awaited
  await Hive.openBox('session'); // Open a box for session management
  await Hive.openBox('settings'); // Open a box for theme settings

  final settingsBox = Hive.box('settings');
  final isDarkMode = settingsBox.get('isDarkMode', defaultValue: false);

  runApp(MyApp());
}

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(
    Hive.box('settings').get('isDarkMode', defaultValue: false)
        ? ThemeMode.dark
        : ThemeMode.light);

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _offsetAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);

    _offsetAnimation = Tween<Offset>(
      begin: const Offset(-0.5, 0.0),
      end: const Offset(0.5, 0.0),
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));

    _checkAuthStatus();
  }

  // This function determines the correct screen to show after the splash screen.
  Future<void> _checkAuthStatus() async {
    // A delay to simulate loading and ensure the splash is visible.
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final sessionBox = Hive.box('session');
    final String? userId = sessionBox.get('userId');

    if (userId == null) {
      // No user is logged in
      Navigator.of(context)
          .pushReplacement(MaterialPageRoute(builder: (_) => AuthScreen()));
    } else {
      // A user is logged in, verify their setup status
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .get();
        if (!mounted) return;

        // Check which businesses the user has access to
        final businessesSnapshot = await FirebaseFirestore.instance
            .collection('businesses')
            .where('members', arrayContains: userId)
            .get();

        if (!mounted) return;

        if (businessesSnapshot.docs.isEmpty) {
          // No businesses associated, go to setup
          Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => BusinessSetupScreen()));
        } else if (businessesSnapshot.docs.length == 1) {
          // Only one business, select it automatically
          final businessId = businessesSnapshot.docs.first.id;
          sessionBox.put('currentBusinessId', businessId);
          await _loadUserData(userId, businessId);
          Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => BottomNavScreen()));
        } else {
          // Multiple businesses, let the user choose
          Navigator.of(context).pushReplacement(MaterialPageRoute(
              builder: (_) => BusinessSelectionScreen(
                  businesses: businessesSnapshot.docs)));
        }
      } catch (e) {
        print("Error checking auth status: $e");
        // If something goes wrong, log them out.
        sessionBox.delete('userId');
        Navigator.of(context)
            .pushReplacement(MaterialPageRoute(builder: (_) => AuthScreen()));
      }
    }
    _loadUserData(userId);
  }

  Future<void> _loadUserData(String? userId, [String? businessId]) async {
    if (userId == null || businessId == null) return;

    try {
      // Load Products
      final productsSnapshot = await FirebaseFirestore.instance
          .collection('products')
          .where('businessId', isEqualTo: businessId)
          .get();
      final userProducts = productsSnapshot.docs
          .map((doc) => Product.fromFirestore(doc))
          .toList();
      products.value = userProducts;

      // Load Invoices
      final invoicesSnapshot = await FirebaseFirestore.instance
          .collection('invoices')
          .where('businessId', isEqualTo: businessId)
          .orderBy('date', descending: true)
          .get();
      final userInvoices = invoicesSnapshot.docs
          .map((doc) => Invoice.fromFirestore(doc))
          .toList();
      invoices.value = userInvoices;
    } catch (e) {
      print("Failed to load user data: $e");
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SlideTransition(
          position: _offsetAnimation,
          child: Image.asset('assets/trolley.png', width: 75, height: 75),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, ThemeMode currentMode, __) {
        // Determine the user's locale for currency formatting.
        Locale systemLocale = ui.window.locale;
        String countryCode =
            systemLocale.countryCode ?? "US"; // Default to "US" if null

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: Locale('en', countryCode),
          title: 'CartEase',
          theme: ThemeData(
            brightness: Brightness.light,
            primarySwatch: Colors.blue,
            scaffoldBackgroundColor: Colors.white,
            cardColor: Colors.white,
            colorScheme: ColorScheme.light(
              primary: Colors.blue,
              secondary: Colors.orange,
              surface: Colors.white,
              error: Colors.red,
              onPrimary: Colors.white,
              onSecondary: Colors.white,
              onSurface: Colors.black87,
              onError: Colors.white,
              brightness: Brightness.light,
            ),
            fontFamily: GoogleFonts.poppins().fontFamily,
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primarySwatch: Colors.blue,
            scaffoldBackgroundColor: Color(0xFF121212),
            cardColor: Color(0xFF1E1E1E),
            appBarTheme:
                AppBarTheme(backgroundColor: Color.fromARGB(255, 27, 27, 27)),
            fontFamily: GoogleFonts.poppins().fontFamily,
          ),
          themeMode: currentMode,
          home: SplashScreen(), // Always start with the splash screen.
        );
      },
    );
  }
}

// Model for Scanned Items
class ScannedItem {
  final String name;
  final double cost;
  final String barcode;
  final String? imageUrl;
  int quantity;

  ScannedItem(
      {required this.name,
      required this.cost,
      required this.barcode,
      this.imageUrl,
      this.quantity = 1});

  // Method to convert a ScannedItem to a map for Firestore
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'cost': cost,
      'barcode': barcode,
      'imageUrl': imageUrl,
      'quantity': quantity,
    };
  }

  // Factory constructor to create a ScannedItem from a map
  factory ScannedItem.fromMap(Map<String, dynamic> map) {
    return ScannedItem(
        name: map['name'] ?? '',
        cost: (map['cost'] ?? 0.0).toDouble(),
        barcode: map['barcode'] ?? '',
        imageUrl: map['imageUrl'],
        quantity: map['quantity'] ?? 1);
  }
  factory ScannedItem.fromProduct(Product product) {
    return ScannedItem(
        name: product.name,
        cost: product.cost,
        barcode: product.barcode,
        imageUrl: product.imageUrl,
        quantity: 1);
  }
}

class Product {
  final String? id;
  final String barcode;
  final String name;
  final double cost; // This should be double
  final DateTime date;
  final String? ownerId;
  final String? businessId;
  final String? imageUrl;
  final int? stock;

  Product({
    this.id,
    required this.barcode,
    required this.name,
    required this.cost,
    required this.date,
    this.ownerId,
    this.businessId,
    this.imageUrl,
    this.stock,
  });

  // Factory constructor to create a Product from a Firestore document
  factory Product.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map<String, dynamic>;
    return Product(
      id: doc.id,
      barcode: data['barcode'] ?? '',
      name: data['name'] ?? '',
      cost: (data['cost'] ?? 0.0).toDouble(),
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      ownerId: data['ownerId'],
      businessId: data['businessId'],
      imageUrl: data['imageUrl'],
      stock: data['stock'],
    );
  }

  // Method to convert a Product to a map for Firestore
  Map<String, dynamic> toJson() {
    return {
      'barcode': barcode,
      'name': name,
      'cost': cost,
      'date': Timestamp.fromDate(date),
      'ownerId': ownerId,
      'businessId': businessId,
      'imageUrl': imageUrl,
      'stock': stock,
    };
  }
}

// Model for Invoice
class Invoice {
  final String? id; // Optional: To store the Firestore document ID
  final String invoiceNumber;
  final List<ScannedItem> items;
  final double totalAmount;
  final DateTime date;
  final String? ownerId;
  final String? businessId;
  final String? transactionId;

  Invoice(
      {this.id,
      required this.invoiceNumber,
      required this.items,
      required this.totalAmount,
      required this.date,
      this.ownerId,
      this.businessId,
      this.transactionId});

  // Method to convert an Invoice to a map for Firestore
  Map<String, dynamic> toJson() {
    return {
      'invoiceNumber': invoiceNumber,
      'items': items.map((item) => item.toJson()).toList(),
      'totalAmount': totalAmount,
      'date': Timestamp.fromDate(date),
      'ownerId': ownerId,
      'businessId': businessId,
      'transactionId': transactionId,
    };
  }

  // Factory constructor to create an Invoice from a Firestore document
  factory Invoice.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    var itemsFromDb = data['items'] as List<dynamic>? ?? [];
    List<ScannedItem> invoiceItems =
        itemsFromDb.map((itemData) => ScannedItem.fromMap(itemData)).toList();

    return Invoice(
      id: doc.id,
      invoiceNumber: data['invoiceNumber'] ?? '',
      items: invoiceItems,
      totalAmount: (data['totalAmount'] ?? 0.0).toDouble(),
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      ownerId: data['ownerId'],
      businessId: data['businessId'],
      transactionId: data['transactionId'],
    );
  }
}

class Profile {
  late final String name;
  late final String email;
  late final String phone;

  Profile({required this.name, required this.email, required this.phone});
}

// Global lists to manage scanned items and invoices
// List<ScannedItem> scannedItems = [];
// Use ValueNotifier for the scanned items list to notify changes

ValueNotifier<List<Product>> products = ValueNotifier([]);
ValueNotifier<List<ScannedItem>> scannedItems = ValueNotifier([]);
ValueNotifier<List<Invoice>> invoices = ValueNotifier([]);
String? userCurrencySymbol; // Global variable for the user's currency symbol
//List<Product> products = [];

// Main Screen with Bottom Navigation
class BottomNavScreen extends StatefulWidget {
  const BottomNavScreen({super.key});

  @override
  _BottomNavScreenState createState() => _BottomNavScreenState();
}

class _BottomNavScreenState extends State<BottomNavScreen> {
  String _businessName = 'CartEase'; // Default name
  final TextEditingController _searchController = TextEditingController();
  int _selectedIndex = 0;

  // List of screens to navigate between
  final List<Widget> _screens = [
    DashboardScreen(),
    ScannedListScreen(),
    InvoiceListScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _fetchBusinessName();
  }

  Future<void> _fetchBusinessName() async {
    final doc = await _getUserBusinessData();
    if (doc.exists && mounted) {
      final data = doc.data() as Map<String, dynamic>?;
      setState(() => _businessName = data?['businessName'] ?? 'CartEase');
    }
  }

  Future<DocumentSnapshot> _getUserBusinessData() async {
    final sessionBox = Hive.box('session');
    final String? userId = sessionBox.get('userId');
    final String? businessId = sessionBox.get('currentBusinessId');

    if (userId == null || businessId == null) {
      // Return a dummy snapshot if no user/business is selected
      return FirebaseFirestore.instance
          .collection('businesses')
          .doc('dummy')
          .get();
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('businesses')
          .doc(businessId)
          .get();
      if (doc.exists) {
        final data = doc.data();
        final currencyCode = data?['currency'];
        if (currencyCode != null) {
          // Currency settings
          final Map<String, String> currencyMap = {
            'USD': '\$', // US Dollar
            'EUR': '€', // Euro
            'INR': '₹', // Indian Rupee
            'GBP': '£', // British Pound
            'JPY': '¥', // Japanese Yen
            'AUD': 'A\$', // Australian Dollar
            'CAD': 'C\$', // Canadian Dollar
            'CNY': '¥', // Chinese Yuan
            'CHF': 'CHF', // Swiss Franc
            'SGD': 'S\$', // Singapore Dollar
            'NZD': 'NZ\$', // New Zealand Dollar
            'ZAR': 'R', // South African Rand
            'AED': 'د.إ', // UAE Dirham
            'SAR': '﷼', // Saudi Riyal
            'THB': '฿', // Thai Baht
            'KRW': '₩', // South Korean Won
            'RUB': '₽', // Russian Ruble
            'BRL': 'R\$', // Brazilian Real
            'MXN': 'Mex\$', // Mexican Peso
          };
          userCurrencySymbol = currencyMap[currencyCode];
        }
      }
      return doc;
    } catch (e) {
      print("Failed to load business data for drawer: $e");
      return FirebaseFirestore.instance
          .collection('businesses')
          .doc('dummy')
          .get();
    }
  }

  Future<void> _logout() async {
    final sessionBox = Hive.box('session');
    await sessionBox.delete('userId');

    // ** CRITICAL: Clear all global data on logout **
    products.value = [];
    scannedItems.value = [];
    invoices.value = [];
    await sessionBox.delete('currentBusinessId');

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => AuthScreen()),
      (route) => false,
    );
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Future<void> _selectBusiness(String businessId) async {
    final sessionBox = Hive.box('session');
    await sessionBox.put('currentBusinessId', businessId);

    // Load data for the selected business
    final userId = sessionBox.get('userId');
    if (userId != null) {
      // You might want to show a loading indicator here
      final productsSnapshot = await FirebaseFirestore.instance
          .collection('products')
          .where('businessId', isEqualTo: businessId)
          .get();
      products.value = productsSnapshot.docs
          .map((doc) => Product.fromFirestore(doc))
          .toList();

      final invoicesSnapshot = await FirebaseFirestore.instance
          .collection('invoices')
          .where('businessId', isEqualTo: businessId)
          .orderBy('date', descending: true)
          .get();
      invoices.value = invoicesSnapshot.docs
          .map((doc) => Invoice.fromFirestore(doc))
          .toList();
    }
    // Clear the scanned items list to ensure a fresh start
    scannedItems.value = [];

    // Replace the current screen with the main app screen, ensuring a clean state.
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => BottomNavScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _showSwitchBusinessDialog() async {
    final sessionBox = Hive.box('session');
    final userId = sessionBox.get('userId');
    if (userId == null || !mounted) return;

    // Close the drawer first
    Navigator.pop(context);

    final businessesSnapshot = await FirebaseFirestore.instance
        .collection('businesses')
        .where('members', arrayContains: userId)
        .get();

    if (!mounted) return;

    final String? currentBusinessId = sessionBox.get('currentBusinessId');

    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text("Switch Business"),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: businessesSnapshot.docs.length,
              itemBuilder: (context, index) {
                final business = businessesSnapshot.docs[index];
                final businessData = business.data();
                final bool isCurrent = business.id == currentBusinessId;

                return ListTile(
                  title: Text(
                    businessData['businessName'] ?? 'Unnamed Business',
                    style: TextStyle(
                        fontWeight:
                            isCurrent ? FontWeight.bold : FontWeight.normal),
                  ),
                  trailing: isCurrent
                      ? Icon(Icons.check_circle,
                          color: Theme.of(context).colorScheme.primary)
                      : null,
                  onTap: () {
                    Navigator.pop(dialogContext); // Close the dialog
                    if (!isCurrent) {
                      _selectBusiness(business.id);
                    }
                  },
                );
              },
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text("Cancel"),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            ElevatedButton.icon(
              icon: Icon(Icons.add, size: 18),
              label: Text("Create New"),
              onPressed: () {
                Navigator.of(dialogContext).pop(); // Close the dialog
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => BusinessSetupScreen()),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Future<List<Product>> _searchAcrossBusinesses(String query) async {
    final sessionBox = Hive.box('session');
    final String? userId = sessionBox.get('userId');
    final String? currentBusinessId = sessionBox.get('currentBusinessId');

    if (userId == null) return [];

    try {
      // Find all businesses the user is a member of, excluding the current one.
      final businessesSnapshot = await FirebaseFirestore.instance
          .collection('businesses')
          .where('members', arrayContains: userId)
          .get();

      final otherBusinessIds = businessesSnapshot.docs
          .map((doc) => doc.id)
          .where((id) => id != currentBusinessId)
          .toList();

      if (otherBusinessIds.isEmpty) return [];

      // Search for products in those other businesses.
      final productsSnapshot = await FirebaseFirestore.instance
          .collection('products')
          .where('businessId', whereIn: otherBusinessIds)
          .orderBy('cost', descending: true) // Sort by price descending
          .get();

      // Filter locally since Firestore doesn't support OR queries on different fields.
      return productsSnapshot.docs
          .map((doc) => Product.fromFirestore(doc))
          .where((p) =>
              p.name.toLowerCase().contains(query) ||
              p.barcode.toLowerCase().contains(query))
          .toList();
    } catch (e) {
      print("Error searching across businesses: $e");
      return [];
    }
  }

  void _showProductSearch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.8,
          builder: (BuildContext context, ScrollController scrollController) {
            return StatefulBuilder(
              builder: (BuildContext context, StateSetter setModalState) {
                final searchQuery = _searchController.text.toLowerCase();
                List<Product> localResults = [];
                List<Product> crossBusinessResults = [];
                bool isSearching = false;

                if (searchQuery.isNotEmpty) {
                  localResults = products.value.where((product) {
                    return product.name.toLowerCase().contains(searchQuery) ||
                        product.barcode.toLowerCase().contains(searchQuery);
                  }).toList();
                }

                void performSearch(String query) async {
                  setModalState(() => isSearching = true);
                  final results = await _searchAcrossBusinesses(query);
                  setModalState(() => crossBusinessResults = results);
                }

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: 'Search by name or barcode',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: Icon(Icons.clear),
                                  onPressed: () {
                                    setModalState(() {
                                      _searchController.clear();
                                    });
                                  },
                                )
                              : null,
                        ),
                        onChanged: (value) {
                          setModalState(() {
                            if (localResults.isEmpty && value.isNotEmpty) {
                              performSearch(value.toLowerCase());
                            }
                          });
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 16.0),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: Icon(Icons.add),
                          label: Text('Add New Product'),
                          onPressed: () {
                            Navigator.pop(context); // Close the search sheet
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => AddProductScreen()),
                            );
                          },
                        ),
                      ),
                    ),
                    Expanded(
                      child: localResults.isEmpty && searchQuery.isNotEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('No products found for "$searchQuery".'),
                                  SizedBox(height: 16),
                                  ElevatedButton.icon(
                                    icon: Icon(Icons.add),
                                    label: Text('Add as New Product'),
                                    onPressed: () {
                                      Navigator.pop(
                                          context); // Close the search sheet
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              AddProductScreen(
                                                  barcode: searchQuery),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: ListView.builder(
                                    controller: scrollController,
                                    itemCount: localResults.length,
                                    itemBuilder: (context, index) {
                                      final product = localResults[index];
                                      return ListTile(
                                        title: Text(product.name),
                                        subtitle:
                                            Text('Barcode: ${product.barcode}'),
                                        trailing: Text(
                                            '${userCurrencySymbol ?? getCurrencySymbol(context)}${product.cost.toStringAsFixed(2)}'),
                                        onTap: () {
                                          final existingItemIndex = scannedItems
                                              .value
                                              .indexWhere((item) =>
                                                  item.barcode ==
                                                  product.barcode);
                                          if (existingItemIndex != -1) {
                                            final updatedList =
                                                List<ScannedItem>.from(
                                                    scannedItems.value);
                                            updatedList[existingItemIndex]
                                                .quantity++;
                                            scannedItems.value = updatedList;
                                          } else {
                                            scannedItems.value = [
                                              ...scannedItems.value,
                                              ScannedItem.fromProduct(product)
                                            ];
                                          }
                                          Navigator.pop(
                                              context); // Close the bottom sheet
                                          _onItemTapped(
                                              1); // Switch to the billing screen
                                        },
                                      );
                                    },
                                  ),
                                ),
                                if (crossBusinessResults.isNotEmpty) ...[
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16.0, vertical: 8.0),
                                    child: Text("From other businesses",
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withOpacity(0.7))),
                                  ),
                                  Expanded(
                                    child: ListView.builder(
                                      itemCount: crossBusinessResults.length,
                                      itemBuilder: (context, index) {
                                        final product =
                                            crossBusinessResults[index];
                                        return ListTile(
                                          title: Text(product.name),
                                          subtitle:
                                              Text('From another business'),
                                          trailing: Text(
                                              '${userCurrencySymbol ?? getCurrencySymbol(context)}${product.cost.toStringAsFixed(2)}'),
                                          leading: Icon(Icons.storefront),
                                          onTap: () {
                                            // Not adding to cart as it's from another business
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(SnackBar(
                                                    content: Text(
                                                        "This product is from another business and cannot be added to the current cart.")));
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                ]
                              ],
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    ).then((_) => _searchController.clear()); // Clear search on close
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: Icon(Icons.menu),
            color: Colors.white,
            onPressed: () {
              // Opens the side drawer
              Scaffold.of(context).openDrawer();
            },
          ),
        ),
        centerTitle: true,
        title: Text(
          _businessName,
          style: TextStyle(color: Colors.white),
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                Color.fromARGB(255, 33, 72, 243),
                Color.fromARGB(255, 188, 198, 242)
              ])),
        ),
      ),
      drawer: Drawer(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  FutureBuilder<DocumentSnapshot>(
                    future: _getUserBusinessData(),
                    builder: (context, snapshot) {
                      String businessName = 'CartEase';
                      String businessType = '';

                      if (snapshot.hasData && snapshot.data != null) {
                        final data =
                            snapshot.data!.data() as Map<String, dynamic>?;
                        businessName = data?['businessName'] ?? 'CartEase';
                        businessType = data?['businessType'] ?? '';
                      }

                      return DrawerHeader(
                        decoration: BoxDecoration(
                            gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: <Color>[
                              Color.fromARGB(255, 33, 72, 243),
                              Color.fromARGB(255, 188, 198, 242)
                            ])),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              businessName,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (businessType.isNotEmpty)
                              Text(
                                businessType,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 14,
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.person_2_outlined),
                    title: Text('Profile'),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => UserProfileForm()),
                      );
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.list),
                    title: Text('Products'),
                    onTap: () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => ProductsScreen()));
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.add),
                    title: Text('Add Product'),
                    onTap: () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => AddProductScreen()));
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.business),
                    title: Text('Business Settings'),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => BusinessSettingsScreen()),
                      );
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.payment),
                    title: Text('Payment Settings'),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => PaymentSettingsScreen()),
                      );
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.swap_horiz),
                    title: Text('Switch Business'),
                    onTap: _showSwitchBusinessDialog,
                  ),
                ],
              ),
            ),
            const Divider(),
            SwitchListTile(
              title: Text('Dark Mode'),
              secondary: Icon(Icons.dark_mode_outlined),
              value: themeNotifier.value == ThemeMode.dark,
              onChanged: (isDark) {
                themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
                Hive.box('settings').put('isDarkMode', isDark);
              },
            ),
            ListTile(
              leading: Icon(Icons.logout),
              title: Text('Logout'),
              onTap: _logout,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
      body: _screens[_selectedIndex],
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color.fromARGB(255, 33, 72, 243),
              Color.fromARGB(255, 188, 198, 242)
            ], // Blue gradient
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: BottomNavigationBar(
          backgroundColor: Colors
              .transparent, // Make background transparent for the gradient
          currentIndex: _selectedIndex,
          onTap: _onItemTapped, // Change screen when tab is tapped
          items: [
            BottomNavigationBarItem(
                icon: Icon(Icons.dashboard), label: "Dashboard"),
            BottomNavigationBarItem(icon: Icon(Icons.list), label: "Billing"),
            BottomNavigationBarItem(
                icon: Icon(Icons.receipt), label: "Invoices"),
          ],
          selectedItemColor: Colors.white, // Selected item text color
          unselectedItemColor:
              Colors.white.withOpacity(0.3), // Unselected item text color
        ),
      ),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 32.0), // Adjust left padding
            child: FloatingActionButton(
              onPressed: _showProductSearch,
              heroTag: 'searchProductFab',
              tooltip: 'Search Product',
              child: Icon(Icons.search),
            ),
          ),
          FloatingActionButton(
            onPressed: scanBarcode,
            heroTag: 'scanBarcodeFab',
            tooltip: 'Scan QR',
            child: Icon(Icons.qr_code_scanner_outlined),
          ),
        ],
      ),
    );
  }

  Future<ScannedItem?> _fetchProductFromApi(String barcode) async {
    try {
      print("API request triggered for barcode $barcode");
      final url = Uri.parse(
          'https://world.openfoodfacts.org/api/v0/product/$barcode.json');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 1 && data['product'] != null) {
          final productData = data['product'];
          final productName = productData['product_name'] as String?;
          final imageUrl = productData['image_url'] as String?;

          if (productName != null && productName.isNotEmpty) {
            return ScannedItem(
              name: productName,
              cost: 0.0, // Default cost, user can edit
              barcode: barcode,
              imageUrl: imageUrl,
            );
          }
        }
      } else {
        print(
            "API request failed for barcode $barcode with status code: ${response.statusCode}");
      }
    } catch (e) {
      print("Failed to fetch product from API: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Could not connect to product database.")));
      }
    }
    return null;
  }

  // Function to scan barcode (same as before)
  Future<void> scanBarcode() async {
    final barcodeScanRes = await Navigator.push<String>(
        context, MaterialPageRoute(builder: (context) => const ScannerPage()));

    if (barcodeScanRes != null) {
      Product? matchedProduct;
      try {
        matchedProduct = products.value.firstWhere(
          (aProduct) => aProduct.barcode == barcodeScanRes,
        );
      } catch (e) {
        // This catch block will handle the case where no element is found.
        matchedProduct = null;
      }

      // Check if the item already exists in the scanned list
      final existingItemIndex = scannedItems.value
          .indexWhere((item) => item.barcode == barcodeScanRes);

      if (existingItemIndex != -1) {
        // If item exists, increment its quantity
        final updatedList = List<ScannedItem>.from(scannedItems.value);
        updatedList[existingItemIndex].quantity++;
        scannedItems.value = updatedList;
      } else {
        ScannedItem newItem;
        if (matchedProduct != null) {
          // Product found in local database
          newItem = ScannedItem.fromProduct(matchedProduct);
        } else {
          // Product not found locally, try fetching from API
          final apiProduct = await _fetchProductFromApi(barcodeScanRes);
          newItem = apiProduct ??
              ScannedItem(
                name: 'Sample (Not Found)',
                cost: 0.0, // Default cost for unknown items
                barcode: barcodeScanRes,
              );
        }
        // Add the new item to the list
        scannedItems.value = [...scannedItems.value, newItem];
      }
    } else {
      // This is for testing when no barcode is scanned; you can adjust as needed.
      scannedItems.value = List.from(scannedItems.value)
        ..add(ScannedItem(
            name: 'Sample (Not Found)',
            cost: 10,
            barcode: '123456',
            quantity: 1));
    }

    // Switch to Billing tab and trigger a rebuild
    setState(() {
      _selectedIndex = 1;
    });
  }
}

// Method to get formatted currency symbol
String getCurrencySymbol(BuildContext context) {
  Locale locale = Localizations.localeOf(context);
  return NumberFormat.simpleCurrency(locale: locale.toString()).currencySymbol;
}

// Method to get currency icon based on symbol
// Method to get currency icon based on symbol
IconData getCurrencyIcon(String currencySymbol) {
  switch (currencySymbol) {
    case '\$': // US Dollar, Canadian Dollar, Australian Dollar, etc.
      return Icons.attach_money;
    case '€': // Euro
      return Icons.euro;
    case '£': // British Pound
      return Icons.currency_pound;
    case '₹': // Indian Rupee
      return Icons.currency_rupee;
    case '¥': // Japanese Yen / Chinese Yuan
      return Icons.currency_yen;
    // case '₩': // South Korean Won
    //   return Icons.currency_won;
    case '₽': // Russian Ruble
      return Icons.currency_ruble;
    case '₺': // Turkish Lira
      return Icons.currency_lira;
    case '₫': // Vietnamese Dong
      return Icons.currency_bitcoin; // closest available
    case '฿': // Thai Baht
      return Icons.currency_bitcoin; // closest available
    case '₦': // Nigerian Naira
      return Icons.currency_bitcoin; // closest available
    case '₴': // Ukrainian Hryvnia
      return Icons.currency_bitcoin; // closest available
    case 'د.إ': // UAE Dirham
      return Icons.monetization_on; // generic
    case '﷼': // Saudi Riyal, Qatari Riyal, Omani Rial
      return Icons.monetization_on;
    case 'R': // South African Rand
      return Icons.monetization_on;
    default:
      return Icons.monetization_on; // Fallback generic
  }
}

// Dashboard Screen (Home Screen)
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // This Future is used to ensure business-specific data like currency is loaded.
    final Future<void> initialization = Future(() async {
      if (userCurrencySymbol == null) {
        final sessionBox = Hive.box('session');
        final businessId = sessionBox.get('currentBusinessId');
        if (businessId != null) {
          final doc = await FirebaseFirestore.instance
              .collection('businesses')
              .doc(businessId)
              .get();
          if (doc.exists) {
            final data = doc.data();
            final currencyCode = data?['currency'];
            if (currencyCode != null) {
              // Currency settings
              final Map<String, String> currencyMap = {
                'USD': '\$', // US Dollar
                'EUR': '€', // Euro
                'INR': '₹', // Indian Rupee
                'GBP': '£', // British Pound
                'JPY': '¥', // Japanese Yen
                'AUD': 'A\$', // Australian Dollar
                'CAD': 'C\$', // Canadian Dollar
                'CNY': '¥', // Chinese Yuan
                'CHF': 'CHF', // Swiss Franc
                'SGD': 'S\$', // Singapore Dollar
                'NZD': 'NZ\$', // New Zealand Dollar
                'ZAR': 'R', // South African Rand
                'AED': 'د.إ', // UAE Dirham
                'SAR': '﷼', // Saudi Riyal
                'THB': '฿', // Thai Baht
                'KRW': '₩', // South Korean Won
                'RUB': '₽', // Russian Ruble
                'BRL': 'R\$', // Brazilian Real
                'MXN': 'Mex\$', // Mexican Peso
              };
              userCurrencySymbol = currencyMap[currencyCode];
            }
          }
        }
      }
    });

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: FutureBuilder(
        future: initialization,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          // Once the future is complete, build the actual dashboard.
          return _DashboardContent();
        },
      ),
    );
  }
}

// Date filter options for dashboard metrics
enum DateRangeFilter { today, thisWeek, thisMonth, lastMonth }

class _DashboardContent extends StatefulWidget {
  const _DashboardContent();

  @override
  State<_DashboardContent> createState() => _DashboardContentState();
}

class _DashboardContentState extends State<_DashboardContent> {
  DateRangeFilter _selectedFilter = DateRangeFilter.today;

  String _filterLabel(DateRangeFilter f) {
    switch (f) {
      case DateRangeFilter.today:
        return 'Today';
      case DateRangeFilter.thisWeek:
        return 'This Week';
      case DateRangeFilter.thisMonth:
        return 'This Month';
      case DateRangeFilter.lastMonth:
        return 'Last Month';
    }
  }

  bool _dateMatchesFilter(DateTime d) {
    final now = DateTime.now();
    final date = DateTime(d.year, d.month, d.day);
    final today = DateTime(now.year, now.month, now.day);

    switch (_selectedFilter) {
      case DateRangeFilter.today:
        return date == today;
      case DateRangeFilter.thisWeek:
        final startOfWeek =
            today.subtract(Duration(days: today.weekday - 1)); // Monday start
        final endOfWeek = startOfWeek.add(const Duration(days: 7));
        return date.isAtSameMomentAs(startOfWeek) ||
            (date.isAfter(startOfWeek) && date.isBefore(endOfWeek));
      case DateRangeFilter.thisMonth:
        return d.year == now.year && d.month == now.month;
      case DateRangeFilter.lastMonth:
        final lastMonthDate = DateTime(now.year, now.month - 1, 1);
        return d.year == lastMonthDate.year && d.month == lastMonthDate.month;
    }
  }

  List<Invoice> _filteredInvoices() {
    return invoices.value.where((inv) => _dateMatchesFilter(inv.date)).toList();
  }

  double calculateTotalAmount(List<Invoice> list) {
    return list.fold(0.0, (sum, invoice) => sum + invoice.totalAmount);
  }

  Map<int, double> getMonthlySales() {
    Map<int, double> monthly = {};
    for (var invoice in _filteredInvoices()) {
      int month = invoice.date.month;
      monthly[month] = (monthly[month] ?? 0) + invoice.totalAmount;
    }
    return monthly;
  }

  Map<int, int> getMonthlyOrders() {
    Map<int, int> monthly = {};
    for (var invoice in _filteredInvoices()) {
      int month = invoice.date.month;
      monthly[month] = (monthly[month] ?? 0) + 1;
    }
    return monthly;
  }

  List<FlSpot> _generateSparklineFromInvoices() {
    final monthlySales = getMonthlySales();
    if (monthlySales.isEmpty) {
      return List.generate(12, (index) => FlSpot(index.toDouble(), 0));
    }
    return monthlySales.entries
        .map((entry) => FlSpot((entry.key - 1).toDouble(), entry.value))
        .toList();
  }

  List<FlSpot> _generateSparklineFromOrders() {
    final monthlyOrders = getMonthlyOrders();
    if (monthlyOrders.isEmpty) {
      return List.generate(12, (index) => FlSpot(index.toDouble(), 0));
    }
    return monthlyOrders.entries
        .map((entry) =>
            FlSpot((entry.key - 1).toDouble(), entry.value.toDouble()))
        .toList();
  }

  Widget _metricChip(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _metricCard({
    required BuildContext context,
    required String title,
    required String chipText,
    required IconData icon,
    required String value,
    required double percentChange,
    required List<FlSpot> sparklineData,
  }) {
    bool isPositive = percentChange >= 0;
    return Container(
      height: 180, // Give the card a fixed height
      width: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
            width: 1),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.7)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (chipText.isNotEmpty) _metricChip(context, chipText),
            ],
          ),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                  color: isPositive ? Colors.green : Colors.red, size: 16),
              const SizedBox(width: 4),
              Text('${(percentChange * 100).toStringAsFixed(1)}%',
                  style: TextStyle(
                      color: isPositive ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: false),
                titlesData: FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                      spots: sparklineData,
                      isCurved: true,
                      color: Theme.of(context).colorScheme.primary,
                      barWidth: 2,
                      dotData: FlDotData(show: false)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        // Added ScrollView to handle overflow
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Top Navigation and Search
              const SizedBox(height: 26),
              // Date filter dropdown centered
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outline
                              .withOpacity(0.2)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<DateRangeFilter>(
                        value: _selectedFilter,
                        borderRadius: BorderRadius.circular(12),
                        onChanged: (val) {
                          if (val != null)
                            setState(() => _selectedFilter = val);
                        },
                        items: const [
                          DropdownMenuItem(
                            value: DateRangeFilter.today,
                            child: Text('Today'),
                          ),
                          DropdownMenuItem(
                            value: DateRangeFilter.thisWeek,
                            child: Text('This Week'),
                          ),
                          DropdownMenuItem(
                            value: DateRangeFilter.thisMonth,
                            child: Text('This Month'),
                          ),
                          DropdownMenuItem(
                            value: DateRangeFilter.lastMonth,
                            child: Text('Last Month'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Metrics Cards - Responsive Wrap with chips, % and sparklines
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _metricCard(
                      context: context,
                      title: 'Total Sales',
                      chipText: '',
                      icon: Icons.payments_outlined,
                      value:
                          '${userCurrencySymbol ?? getCurrencySymbol(context)}${calculateTotalAmount(_filteredInvoices()).toStringAsFixed(2)}',
                      percentChange: 0.5,
                      sparklineData: _generateSparklineFromInvoices(),
                    ),
                    const SizedBox(width: 12),
                    _metricCard(
                      context: context,
                      title: 'Total Visitor',
                      chipText: '',
                      icon: Icons.people_alt_outlined,
                      value: '${_filteredInvoices().length * 3}',
                      percentChange: 0.7,
                      sparklineData: _generateSparklineFromOrders(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Total Summary (Sales Overview)
              Container(
                height: 250, // Reduced height
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color:
                        Theme.of(context).colorScheme.outline.withOpacity(0.2),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.trending_up,
                                  color: Colors.green, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Income',
                                  style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  '${userCurrencySymbol ?? getCurrencySymbol(context)}${calculateTotalAmount(invoices.value).toStringAsFixed(2)}',
                                  style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            )
                          ],
                        ),
                        // Removed chip label per request: don't show filter name in cards
                      ],
                    ),
                    const SizedBox(height: 8),
                    const SizedBox(height: 16),
                    Expanded(
                      child: LineChart(
                        LineChartData(
                          gridData: FlGridData(show: false),
                          titlesData: FlTitlesData(
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            rightTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            topTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) {
                                  const months = [
                                    'Jan',
                                    'Feb',
                                    'Mar',
                                    'Apr',
                                    'May',
                                    'Jun',
                                    'Jul',
                                    'Aug',
                                    'Sep',
                                    'Oct',
                                    'Nov',
                                    'Dec'
                                  ];
                                  if (value.toInt() >= 0 &&
                                      value.toInt() < months.length) {
                                    return Text(
                                      // Use theme's text style
                                      months[value.toInt()],
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withOpacity(0.6),
                                        fontSize: 12,
                                      ),
                                    );
                                  }
                                  return const Text('');
                                },
                              ),
                            ),
                          ),
                          borderData: FlBorderData(show: false),
                          lineBarsData: [
                            LineChartBarData(
                              spots: getMonthlySales().entries.map((entry) {
                                int month = entry.key - 1; // Adjust to 0-index
                                double sales = entry.value;
                                return FlSpot(month.toDouble(), sales);
                              }).toList(),
                              isCurved: true,
                              color: Colors.cyan,
                              barWidth: 3,
                              isStrokeCapRound: true,
                              dotData: FlDotData(show: false),
                              belowBarData: BarAreaData(
                                show: true,
                                color: Colors.cyan.withOpacity(0.1),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Top Products and Orders Section (responsive)
              Builder(
                builder: (context) {
                  final screenWidth = MediaQuery.of(context).size.width;
                  final isNarrow = screenWidth < 600;
                  if (isNarrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildTopProductsSection(context),
                        const SizedBox(height: 16),
                        _buildOrdersSection(context),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildTopProductsSection(context)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildOrdersSection(context)),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),

              // Stock Alerts and Comments Section (responsive)
              Builder(
                builder: (context) {
                  final screenWidth = MediaQuery.of(context).size.width;
                  final isNarrow = screenWidth < 600;
                  if (isNarrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildStockAlertsSection(context),
                        const SizedBox(height: 16),
                        _buildCommentsSection(context),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildStockAlertsSection(context)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildCommentsSection(context)),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopProductsSection(BuildContext context) {
    // Calculate top products by quantity sold
    Map<String, int> productQuantities = {};
    for (var invoice in invoices.value) {
      for (var item in invoice.items) {
        productQuantities[item.name] =
            (productQuantities[item.name] ?? 0) + item.quantity;
      }
    }

    var sortedProducts = productQuantities.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    var topProducts = sortedProducts.take(3).toList();

    return SizedBox(
      height: 300,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Top Products',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'This Month',
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (topProducts.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'No products sold yet',
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.5),
                    ),
                  ),
                ),
              )
            else
              ...topProducts.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.shopping_bag,
                          color: Theme.of(context).colorScheme.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.key,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${entry.value} items',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.6),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            if (topProducts.isNotEmpty)
              TextButton(
                onPressed: () {
                  // Navigate to products screen
                },
                child: Text('View All'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersSection(BuildContext context) {
    // Get recent orders (last 3)
    var recentOrders = invoices.value.take(3).toList();

    return SizedBox(
      height: 300,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Order',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'This Month',
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (recentOrders.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'No orders yet',
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.5),
                    ),
                  ),
                ),
              )
            else
              ...recentOrders.map((invoice) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color:
                              Theme.of(context).colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.receipt,
                          color: Theme.of(context).colorScheme.secondary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              invoice.items.isNotEmpty
                                  ? invoice.items.first.name
                                  : 'Order',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              DateFormat('dd MMM yyyy').format(invoice.date),
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.6),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildStockAlertsSection(BuildContext context) {
    // Filter products with low stock (you can adjust the threshold)
    var lowStockProducts =
        products.value.where((p) => (p.stock ?? 0) < 10).take(3).toList();

    return SizedBox(
      height: 300,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Stock Alerts',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton(
                  onPressed: () {},
                  child: Text('View All', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (lowStockProducts.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'All products in stock',
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.5),
                    ),
                  ),
                ),
              )
            else
              ...lowStockProducts.map((product) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: product.imageUrl != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  product.imageUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Icon(
                                    Icons.inventory,
                                    color: Colors.orange,
                                    size: 20,
                                  ),
                                ),
                              )
                            : Icon(
                                Icons.inventory,
                                color: Colors.orange,
                                size: 20,
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              product.name,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'Stock: ${product.stock ?? 0}',
                              style: TextStyle(
                                color: Colors.orange,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildCommentsSection(BuildContext context) {
    return SizedBox(
      height: 300,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Comments',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'This Week',
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Icon(
                      Icons.comment_outlined,
                      size: 48,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.3),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No comments yet',
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _buildMetricCard({
  required BuildContext context,
  required IconData icon,
  required String value,
  required String label,
  required Color color,
}) {
  return SizedBox(
    width: 150, // Fixed width for metric cards
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // Use theme's card color
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 8),
          Text(
            value, // Use theme's text style
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            // Use theme's text style
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  fontSize: 14,
                ),
          ),
        ],
      ),
    ),
  );
}

// Scanned List Screen
class ScannedListScreen extends StatefulWidget {
  const ScannedListScreen({super.key});

  @override
  _ScannedListScreenState createState() => _ScannedListScreenState();
}

class _ScannedListScreenState extends State<ScannedListScreen> {
  // Function to calculate total amount
  bool isButtonEnabled = false;
  double calculateTotalAmount() {
    return scannedItems.value.fold(0, (sum, item) => sum + item.cost);
  }

  void _deleteItem(int index) {
    scannedItems.value = List.from(scannedItems.value)..removeAt(index);
  }

  void _editAndAddProduct(ScannedItem item, int index) {
    // Navigate to AddProductScreen, pre-filling the barcode
    Navigator.push<Product>(
      context,
      MaterialPageRoute(
        builder: (context) => AddProductScreen(
          barcode: item.barcode,
          isEditingScannedItem: true,
        ),
      ),
    ).then((newProduct) {
      if (newProduct != null) {
        // Replace the 'Sample' item with the newly created product
        final updatedScannedItem = ScannedItem.fromProduct(newProduct);
        final newList = List<ScannedItem>.from(scannedItems.value);
        newList[index] = updatedScannedItem;
        scannedItems.value = newList;
      }
    });
  }

  void _updateQuantity(int index, int change) {
    final updatedList = List<ScannedItem>.from(scannedItems.value);
    final currentQuantity = updatedList[index].quantity;

    if (currentQuantity + change <= 0) {
      // If quantity becomes zero or less, remove the item
      _deleteItem(index);
    } else {
      updatedList[index].quantity += change;
      scannedItems.value = updatedList;
    }
  }

  String _formatLineTotal(ScannedItem item) {
    final lineTotal = item.cost * item.quantity;
    return '${userCurrencySymbol ?? getCurrencySymbol(context)}${lineTotal.toStringAsFixed(2)}';
  }

  Widget customListTile(String title, Color color) {
    return Container(
      color: color, // Set the background color here
      child: ListTile(
        title: Text(title),
        onTap: () {
          print('$title tapped');
        },
      ),
    );
  }

  void _showImageDialog(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Dialog(
          child: GestureDetector(
            onTap: () => Navigator.of(dialogContext).pop(),
            child: Image.network(imageUrl, fit: BoxFit.contain),
          ),
        );
      },
    );
  }

  void _confirmClearItems() {
    if (scannedItems.value.isEmpty) return;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('Clear All Items?'),
          content: Text(
              'Are you sure you want to remove all items from the billing list?'),
          actions: <Widget>[
            TextButton(
              child: Text('Cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            TextButton(
              child: Text('Clear All', style: TextStyle(color: Colors.red)),
              onPressed: () {
                scannedItems.value = [];
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    // The currency is loaded globally when a business is selected.
  }

  @override
  Widget build(BuildContext context) {
    isButtonEnabled = scannedItems.value.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text('Billing'),
        actions: [
          ValueListenableBuilder<List<ScannedItem>>(
            valueListenable: scannedItems,
            builder: (context, items, child) {
              if (items.isEmpty) return SizedBox.shrink(); // Hide if no items
              return IconButton(
                icon: Icon(Icons.delete_sweep_outlined),
                onPressed: _confirmClearItems,
                tooltip: 'Clear All Items',
              );
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<List<ScannedItem>>(
        valueListenable: scannedItems,
        builder: (context, items, _) {
          final totalAmount =
              items.fold(0.0, (sum, item) => sum + (item.cost * item.quantity));
          return Column(
            children: [
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(
                          'No items scanned yet.',
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.6),
                              fontSize: 16),
                        ),
                      )
                    : ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            dense: true,
                            tileColor: index % 2 == 0
                                ? Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest
                                    .withOpacity(0.3)
                                : Colors.transparent,
                            leading: GestureDetector(
                              onTap: item.imageUrl != null
                                  ? () =>
                                      _showImageDialog(context, item.imageUrl!)
                                  : null,
                              child: item.imageUrl != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(8.0),
                                      child: Image.network(
                                        item.imageUrl!,
                                        width: 50,
                                        height: 50,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                Icon(Icons.image_not_supported),
                                      ),
                                    )
                                  : Icon(Icons.shopping_cart),
                            ),
                            title: Text(
                              item.name,
                              style: TextStyle(
                                  fontSize: 16,
                                  color:
                                      Theme.of(context).colorScheme.onSurface),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${userCurrencySymbol ?? getCurrencySymbol(context)}${item.cost.toStringAsFixed(2)}',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withOpacity(0.7)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.remove_circle_outline,
                                      size: 20),
                                  onPressed: () => _updateQuantity(index, -1),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                      minWidth: 32, minHeight: 32),
                                ),
                                Text('${item.quantity}',
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold)),
                                IconButton(
                                  icon:
                                      Icon(Icons.add_circle_outline, size: 20),
                                  onPressed: () => _updateQuantity(index, 1),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                      minWidth: 32, minHeight: 32),
                                ),
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 72, // Compact width for total
                                  child: Text(
                                    _formatLineTotal(item),
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface),
                                    textAlign: TextAlign.end,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (item.name == 'Sample (Not Found)')
                                  IconButton(
                                    icon: Icon(Icons.add_circle,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary),
                                    tooltip: 'Add to Products',
                                    onPressed: () =>
                                        _editAndAddProduct(item, index),
                                  )
                                else if (item.name != 'Sample (Not Found)')
                                  const SizedBox(
                                      width:
                                          24), // Smaller placeholder to align items
                              ],
                            ),
                            onLongPress: () => _deleteItem(index),
                            onTap: () {
                              if (item.name == 'Sample (Not Found)') {
                                _editAndAddProduct(item, index);
                              }
                            },
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor:
                            Theme.of(context).colorScheme.onPrimary,
                        elevation: 5,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: items.isNotEmpty
                          ? () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      PaymentScreen(totalAmount: totalAmount),
                                ),
                              );
                            }
                          : null,
                      child: Text(
                        'Proceed to Payment',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              )
            ],
          );
        },
      ),
    );
  }
}

// Payment Screen
class PaymentScreen extends StatelessWidget {
  final double totalAmount;

  const PaymentScreen({super.key, required this.totalAmount});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pay Now'),
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: _getBusinessDetails(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Center(child: Text("Could not load payment details."));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>?;
          final upiId = data?['upiId'] ?? 'your-upi-id@bank'; // Fallback
          final payeeName = data?['payeeName'] ?? 'Your Name'; // Fallback
          final currency = data?['currency'] ?? 'INR';

          String upiUrl =
              'upi://pay?pa=$upiId&pn=$payeeName&am=${totalAmount.toStringAsFixed(2)}&cu=$currency';

          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Scan this QR code to pay',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface),
                ),
                const SizedBox(height: 16),
                QrImageView(
                  data: upiUrl,
                  version: QrVersions.auto,
                  size: 200.0,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("Total Amount: ",
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface)),
                    Text(
                      userCurrencySymbol ?? getCurrencySymbol(context),
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface),
                    ),
                    Text(totalAmount.toStringAsFixed(2),
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface)),
                  ],
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    elevation: 5, // Optional: Customize elevation
                  ),
                  onPressed: () async {
                    await completePayment(context);
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: Text('OK'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<DocumentSnapshot> _getBusinessDetails() async {
    final sessionBox = Hive.box('session');
    final String? businessId = sessionBox.get('currentBusinessId');
    return FirebaseFirestore.instance
        .collection('businesses')
        .doc(businessId)
        .get();
  }

  // Function to complete payment and create invoice
  Future<void> completePayment(BuildContext context) async {
    if (scannedItems.value.isEmpty) return;

    final sessionBox = Hive.box('session');
    final String? userId = sessionBox.get('userId');
    final String? businessId = sessionBox.get('currentBusinessId');

    if (userId == null || businessId == null) {
      if (context.mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Error: Not logged in.")));
      return;
    }

    final now = DateTime.now();
    final datePrefix = DateFormat('yyyyMMdd').format(now);

    try {
      // --- Generate Invoice Number ---
      // 1. Find the start and end of the current day.
      final startOfToday = DateTime(now.year, now.month, now.day);
      final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);

      // 2. Query for invoices created today for this business.
      final querySnapshot = await FirebaseFirestore.instance
          .collection('invoices')
          .where('businessId', isEqualTo: businessId)
          .where('date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfToday))
          .get();

      // 3. Create the sequential number.
      final sequenceNumber =
          (querySnapshot.docs.length + 1).toString().padLeft(4, '0');
      final newInvoiceNumber = '$datePrefix-$sequenceNumber';

      // Generate a mock transaction ID
      final transactionId =
          'TXN${now.millisecondsSinceEpoch}${Random().nextInt(999)}';

      final correctTotalAmount = scannedItems.value
          .fold(0.0, (sum, item) => sum + (item.cost * item.quantity));

      // Create a new invoice object
      final newInvoice = Invoice(
        invoiceNumber: newInvoiceNumber,
        items: List.from(scannedItems.value), // Create a copy
        totalAmount: correctTotalAmount, // Use the correctly calculated total
        date: DateTime.now(),
        ownerId: userId,
        businessId: businessId,
        transactionId: transactionId,
      );

      // Save the new invoice to Firestore
      final docRef = await FirebaseFirestore.instance
          .collection('invoices')
          .add(newInvoice.toJson());

      // Add to local list and clear scanned items
      final newInvoiceFromDb = Invoice.fromFirestore(await docRef.get());
      final currentInvoices = List<Invoice>.from(invoices.value);
      invoices.value = [newInvoiceFromDb, ...currentInvoices];
      scannedItems.value = []; // Clear the cart

      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Payment successful! Invoice created.')));
    } on FirebaseException catch (e) {
      print('Failed to save invoice: $e');
      String errorMessage = 'Failed to save invoice: ${e.message}';
      if (e.code == 'failed-precondition') {
        errorMessage =
            'Database requires an index. Please check the logs for a link to create it.';
      }
      if (context.mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorMessage)));
    } catch (e) {
      print('Failed to save invoice: $e');
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to save invoice: $e')));
    }
  }
}

// Invoice List Screen
class InvoiceListScreen extends StatefulWidget {
  const InvoiceListScreen({super.key});

  @override
  State<InvoiceListScreen> createState() => _InvoiceListScreenState();
}

class _InvoiceListScreenState extends State<InvoiceListScreen> {
  Future<void> _refreshInvoices() async {
    final sessionBox = Hive.box('session');
    final String? businessId = sessionBox.get('currentBusinessId');
    if (businessId == null) return;

    try {
      final invoicesSnapshot = await FirebaseFirestore.instance
          .collection('invoices')
          .where('businessId', isEqualTo: businessId)
          .orderBy('date', descending: true)
          .get();
      invoices.value = invoicesSnapshot.docs
          .map((doc) => Invoice.fromFirestore(doc))
          .toList();
    } catch (e) {
      print("Failed to refresh invoices: $e");
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Failed to refresh invoices.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Invoices'),
      ),
      body: ValueListenableBuilder(
        valueListenable: invoices,
        builder: (context, invoiceList, __) {
          if (invoiceList.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long,
                      size: 64, color: Theme.of(context).colorScheme.outline),
                  SizedBox(height: 16),
                  Text(
                    'No invoices yet',
                    style: TextStyle(
                        fontSize: 18,
                        color: Theme.of(context).colorScheme.onSurface),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Create your first invoice by scanning items and completing payment',
                    style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.7)),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _refreshInvoices,
            child: ListView.builder(
              itemCount: invoiceList.length,
              itemBuilder: (context, index) {
                final invoice = invoiceList[index];
                return Card(
                  margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    tileColor: index % 2 == 0
                        ? Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withOpacity(0.2)
                        : Theme.of(context).cardColor,
                    title: Text(
                      // Use the generated invoice number
                      'Invoice #${invoice.invoiceNumber}',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface),
                    ),
                    subtitle: Text(
                      'Date: ${invoice.date.toString().split(' ')[0]}',
                      style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.7)),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${userCurrencySymbol ?? getCurrencySymbol(context)}${invoice.totalAmount.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              InvoiceDetailScreen(invoice: invoice),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// Invoice Detail Screen
class InvoiceDetailScreen extends StatelessWidget {
  final Invoice invoice;

  void _showImageDialog(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Dialog(
          child: GestureDetector(
            onTap: () => Navigator.of(dialogContext).pop(),
            child: Image.network(imageUrl, fit: BoxFit.contain),
          ),
        );
      },
    );
  }

  const InvoiceDetailScreen({super.key, required this.invoice});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Invoice #${invoice.invoiceNumber}'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Date: ${invoice.date}',
                style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSurface)),
            if (invoice.transactionId != null) ...[
              SizedBox(height: 8),
              Text('Transaction ID: ${invoice.transactionId}',
                  style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.7))),
            ],
            SizedBox(height: 16),
            Text('Items:',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface)),
            Expanded(
              child: ListView.builder(
                itemCount: invoice.items.length,
                itemBuilder: (context, index) {
                  final item = invoice.items[index];
                  return ListTile(
                    leading: GestureDetector(
                      onTap: item.imageUrl != null
                          ? () => _showImageDialog(context, item.imageUrl!)
                          : null,
                      child: item.imageUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8.0),
                              child: Image.network(item.imageUrl!,
                                  width: 50,
                                  height: 50,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Icon(Icons.image_not_supported)),
                            )
                          : Icon(Icons.shopping_cart),
                    ),
                    tileColor: index % 2 == 0
                        ? Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withOpacity(0.2)
                        : Colors.transparent,
                    title: Text('${item.name} (x${item.quantity})',
                        style: TextStyle(
                            fontSize: 16,
                            color: Theme.of(context).colorScheme.onSurface)),
                    subtitle: Text(
                        'Price: ${userCurrencySymbol ?? getCurrencySymbol(context)}${item.cost.toStringAsFixed(2)}',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.7))),
                    trailing: Text(
                        '${userCurrencySymbol ?? getCurrencySymbol(context)}${(item.cost * item.quantity).toStringAsFixed(2)}',
                        style: TextStyle(
                            fontSize: 16,
                            color: Theme.of(context).colorScheme.onSurface)),
                  );
                },
              ),
            ),
            SizedBox(height: 16),
            Text(
                'Total: ${userCurrencySymbol ?? getCurrencySymbol(context)}${invoice.totalAmount.toStringAsFixed(2)}',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary)),
          ],
        ),
      ),
    );
  }
}

class UserProfileForm extends StatefulWidget {
  const UserProfileForm({super.key});

  @override
  _UserProfileFormState createState() => _UserProfileFormState();
}

class _UserProfileFormState extends State<UserProfileForm> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSavedDetails();
  }

  Future<void> _loadSavedDetails() async {
    try {
      final sessionBox = Hive.box('session');
      final String? userId = sessionBox.get('userId');
      if (userId != null) {
        DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .get();
        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>?;
          setState(() {
            _nameController.text = data?['name'] ?? '';
            _emailController.text = data?['email'] ?? '';
            _phoneController.text = data?['phone'] ?? '';
          });
        }
      }
    } catch (e) {
      print('Failed to load profile: ${e.toString()}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load profile: ${e.toString()}')),
      );
    }
  }

  Future<void> _saveDetails() async {
    try {
      final sessionBox = Hive.box('session');
      final String? userId = sessionBox.get('userId');
      if (userId != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .update({
          'name': _nameController.text.trim(),
          'email': _emailController.text.trim(),
          'phone': _phoneController.text.trim(),
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Profile Updated and Saved Successfully')),
        );
      }
    } catch (e) {
      print('Failed to save profile: ${e.toString()}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save profile: ${e.toString()}')),
      );
    }
  }

  void _updateProfile() {
    if (_formKey.currentState!.validate()) {
      _saveDetails();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('User Profile')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Name',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface),
                ),
                SizedBox(height: 8),
                // Name Field
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    // labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your name';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),

                Text(
                  'Email',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface),
                ),
                SizedBox(height: 8),
                // Email Field
                TextFormField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    // labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your email';
                    }
                    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                      return 'Please enter a valid email address';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),

                Text(
                  'Phone',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface),
                ),
                SizedBox(height: 8),
                // Phone Field
                TextFormField(
                  controller: _phoneController,
                  decoration: InputDecoration(
                    // labelText: 'Phone',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your phone number';
                    }
                    if (!RegExp(r'^\d{10}$').hasMatch(value)) {
                      return 'Please enter a valid 10-digit phone number';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),

                // Centered Update Button
                Center(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      elevation: 5, // Optional: Customize elevation
                    ),
                    onPressed: _updateProfile,
                    child: Text('Update Profile',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        )),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AddProductScreen extends StatefulWidget {
  final String? barcode;
  final bool isEditingScannedItem;
  const AddProductScreen({
    super.key,
    this.barcode,
    this.isEditingScannedItem = false,
  });

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final TextEditingController _field1Controller = TextEditingController();
  final TextEditingController _field2Controller = TextEditingController();
  final TextEditingController _field3Controller = TextEditingController();
  final TextEditingController _field4Controller = TextEditingController();
  Uint8List? _imageBytes;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    if (widget.barcode != null) {
      _field1Controller.text = widget.barcode!;
    }
  }

  @override
  void dispose() {
    _field1Controller.dispose();
    _field2Controller.dispose();
    _field3Controller.dispose();
    _field4Controller.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: source);

    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        _imageBytes = bytes;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: Text('Add Product')),
        body: Padding(
          padding: const EdgeInsets.all(50.0),
          child: Column(
            children: [
              GestureDetector(
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    builder: (BuildContext context) {
                      return SafeArea(
                        child: Wrap(
                          children: <Widget>[
                            ListTile(
                                leading: Icon(Icons.photo_library),
                                title: Text('Gallery'),
                                onTap: () {
                                  _pickImage(ImageSource.gallery);
                                  Navigator.of(context).pop();
                                }),
                            ListTile(
                                leading: Icon(Icons.photo_camera),
                                title: Text('Camera'),
                                onTap: () {
                                  _pickImage(ImageSource.camera);
                                  Navigator.of(context).pop();
                                }),
                          ],
                        ),
                      );
                    },
                  );
                },
                child: Container(
                  height: 150,
                  width: 150,
                  decoration:
                      BoxDecoration(border: Border.all(color: Colors.grey)),
                  child: _imageBytes != null
                      ? Image.memory(_imageBytes!, fit: BoxFit.cover)
                      : Center(child: Icon(Icons.add_a_photo, size: 50)),
                ),
              ),
              TextField(
                controller: _field1Controller,
                decoration: InputDecoration(labelText: 'Name'),
              ),
              SizedBox(height: 16),
              TextField(
                controller: _field2Controller,
                decoration: InputDecoration(labelText: 'Name'),
              ),
              SizedBox(height: 16),
              TextField(
                controller: _field3Controller,
                decoration: InputDecoration(labelText: 'Cost'),
              ),
              SizedBox(height: 16),
              TextField(
                controller: _field4Controller,
                decoration: InputDecoration(labelText: 'Stock'),
              ),
              SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  elevation: 5, // Optional: Customize elevation
                ),
                onPressed: _isUploading ? null : _saveProduct,
                child: _isUploading
                    ? CircularProgressIndicator(color: Colors.white)
                    : Text('Save',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        )),
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: addBarcode,
          heroTag: 'addProductScanFab',
          tooltip: 'Scan QR',
          child: Icon(Icons.qr_code_scanner_outlined),
        ));
  }

  Future<void> _saveProduct() async {
    final sessionBox = Hive.box('session');
    final String? userId = sessionBox.get('userId');
    final String? businessId = sessionBox.get('currentBusinessId');

    if (userId == null || businessId == null) {
      print("Save product error: Not logged in.");
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Not logged in.")));
      return;
    }
    if (_field1Controller.text.isEmpty ||
        _field2Controller.text.isEmpty ||
        _field3Controller.text.isEmpty) {
      print("Save product error: All fields not filled.");
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Please fill all fields.")));
      return;
    }

    setState(() => _isUploading = true);

    String? imageUrl;
    if (_imageBytes != null) {
      imageUrl = await ImageUploader.uploadImage(_imageBytes!);
    }

    final newProduct = Product(
      barcode: _field1Controller.text,
      name: _field2Controller.text,
      cost: double.tryParse(_field3Controller.text) ?? 0.0,
      date: DateTime.now(),
      stock: int.tryParse(_field4Controller.text),
      ownerId: userId,
      businessId: businessId,
      imageUrl: imageUrl,
    );

    try {
      await FirebaseFirestore.instance
          .collection('products')
          .add(newProduct.toJson());
      products.value = [...products.value, newProduct]; // Update local list
      if (widget.isEditingScannedItem) {
        // If we were editing a scanned item, pop with the new product
        Navigator.pop(context, newProduct);
      } else {
        Navigator.pop(context); // Go back after saving
      }
    } catch (e) {
      print("Failed to save product: $e");
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Failed to save product: $e")));
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> addBarcode() async {
    // We push the scanner and wait for the result to come back.
    final String? barcode = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const ScannerPage()),
    );

    // If a barcode was returned, update the controller and the UI.
    if (barcode != null && mounted) {
      setState(() {
        _field1Controller.text = barcode;
      });
    }
  }
}

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refreshProducts() async {
    final sessionBox = Hive.box('session');
    final String? businessId = sessionBox.get('currentBusinessId');
    if (businessId == null) return;

    try {
      final productsSnapshot = await FirebaseFirestore.instance
          .collection('products')
          .where('businessId', isEqualTo: businessId)
          .get();
      products.value = productsSnapshot.docs
          .map((doc) => Product.fromFirestore(doc))
          .toList();
    } catch (e) {
      print("Failed to refresh products: $e");
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Failed to refresh products.")));
    }
  }

  void _showImageDialog(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Dialog(
          child: GestureDetector(
            onTap: () => Navigator.of(dialogContext).pop(),
            child: Image.network(imageUrl, fit: BoxFit.contain),
          ),
        );
      },
    );
  }

  Future<void> _deleteItem(int index) async {
    final productToDelete = products.value[index];
    final productId = productToDelete.id;

    if (productId == null) {
      print("Delete product error: Cannot delete product without an ID.");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: Cannot delete product without an ID.")),
      );
      return;
    }

    final sessionBox = Hive.box('session');
    final String? userId = sessionBox.get('userId');
    final String? businessId = sessionBox.get('currentBusinessId');

    try {
      // Delete from Firestore
      await FirebaseFirestore.instance
          .collection('products')
          .doc(productId)
          .delete();

      // Update local state
      products.value = List.from(products.value)..removeAt(index);
    } catch (e) {
      print("Failed to delete product: $e");
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to delete product: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Products')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search by name or barcode',
                prefixIcon: Icon(Icons.search),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshProducts,
              child: ValueListenableBuilder<List<Product>>(
                valueListenable: products,
                builder: (context, items, _) {
                  final filteredProducts = items.where((product) {
                    final query = _searchQuery.toLowerCase();
                    return product.name.toLowerCase().contains(query) ||
                        product.barcode.toLowerCase().contains(query);
                  }).toList();

                  if (items.isEmpty) {
                    return Center(
                      child: Text(
                        'No products found. Add one from the side menu.',
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.6)),
                      ),
                    );
                  }

                  if (filteredProducts.isEmpty && _searchQuery.isNotEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('No products found for "$_searchQuery".'),
                          SizedBox(height: 16),
                          ElevatedButton.icon(
                            icon: Icon(Icons.add),
                            label: Text('Add as New Product'),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      AddProductScreen(barcode: _searchQuery),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: filteredProducts.length,
                    itemBuilder: (context, index) {
                      final product = filteredProducts[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: product.imageUrl != null
                                    ? () => _showImageDialog(
                                        context, product.imageUrl!)
                                    : null,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: product.imageUrl != null
                                      ? Image.network(
                                          product.imageUrl!,
                                          width: 60,
                                          height: 60,
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (context, error, stackTrace) =>
                                                  Container(
                                                      width: 60,
                                                      height: 60,
                                                      color: Colors.grey[200],
                                                      child: Icon(Icons.error)),
                                        )
                                      : Container(
                                          width: 60,
                                          height: 60,
                                          color: Colors.grey[200],
                                          child: Icon(Icons.image_not_supported,
                                              color: Colors.grey[400]),
                                        ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              // Details
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      product.name,
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${userCurrencySymbol ?? getCurrencySymbol(context)}${product.cost.toStringAsFixed(2)}',
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                          fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Barcode: ${product.barcode}',
                                      style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              // Action Buttons
                              IconButton(
                                icon: Icon(Icons.edit,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .secondary),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          ProductDetailScreen(product: product),
                                    ),
                                  ).then((_) => setState(
                                      () {})); // Refresh list on return
                                },
                              ),
                              IconButton(
                                icon: Icon(Icons.delete,
                                    color: Theme.of(context).colorScheme.error),
                                onPressed: () =>
                                    _deleteItem(items.indexOf(product)),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProductDetailScreen extends StatefulWidget {
  final Product product;
  const ProductDetailScreen({super.key, required this.product});

  @override
  _ProductDetailScreenState createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  final TextEditingController _field1Controller = TextEditingController();
  final TextEditingController _field2Controller = TextEditingController();
  final TextEditingController _field3Controller = TextEditingController();
  final TextEditingController _field4Controller = TextEditingController();
  Uint8List? _imageBytes;
  bool _isUploading = false;
  String? _existingImageUrl;

  @override
  void initState() {
    super.initState();
    _field1Controller.text = widget.product.barcode;
    _field2Controller.text = widget.product.name;
    _field3Controller.text = widget.product.cost.toString();
    _field4Controller.text = widget.product.stock?.toString() ?? '';
    _existingImageUrl = widget.product.imageUrl;
  }

  @override
  void dispose() {
    _field1Controller.dispose();
    _field2Controller.dispose();
    _field3Controller.dispose();
    _field4Controller.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: source);

    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        _imageBytes = bytes;
        _existingImageUrl = null; // Clear existing image if new one is picked
      });
    }
  }

  Future<void> _updateProduct() async {
    setState(() => _isUploading = true);

    final sessionBox = Hive.box('session');
    final String? businessId = sessionBox.get('currentBusinessId');

    if (businessId == null || widget.product.id == null) {
      print("Update product error: Business ID or Product ID is null.");
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: Cannot update product.")));
      setState(() => _isUploading = false);
      return;
    }

    String? imageUrl = widget.product.imageUrl;
    if (_imageBytes != null) {
      imageUrl = await ImageUploader.uploadImage(_imageBytes!);
    }

    final updatedProductData = {
      'barcode': _field1Controller.text,
      'name': _field2Controller.text,
      'cost': double.tryParse(_field3Controller.text) ?? 0.0,
      'stock': int.tryParse(_field4Controller.text),
      'imageUrl': imageUrl,
    };

    try {
      await FirebaseFirestore.instance
          .collection('products')
          .doc(widget.product.id)
          .update(updatedProductData);

      // Update local list
      final index = products.value.indexWhere((p) => p.id == widget.product.id);
      if (index != -1) {
        final updatedProduct = Product(
          id: widget.product.id,
          barcode: _field1Controller.text,
          name: _field2Controller.text,
          cost: double.tryParse(_field3Controller.text) ?? 0.0,
          date: widget.product.date, // Keep original date
          stock: int.tryParse(_field4Controller.text),
          imageUrl: imageUrl,
        );
        final newList = List<Product>.from(products.value);
        newList[index] = updatedProduct;
        products.value = newList;
      }

      Navigator.pop(context);
    } catch (e) {
      print("Failed to update product: $e");
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to update product: $e")));
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: Text('Update Product')),
        body: Padding(
          padding: const EdgeInsets.all(50.0),
          child: SingleChildScrollView(
              child: Column(
            children: [
              GestureDetector(
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    builder: (BuildContext context) {
                      return SafeArea(
                        child: Wrap(
                          children: <Widget>[
                            ListTile(
                                leading: Icon(Icons.photo_library),
                                title: Text('Gallery'),
                                onTap: () {
                                  _pickImage(ImageSource.gallery);
                                  Navigator.of(context).pop();
                                }),
                            ListTile(
                                leading: Icon(Icons.photo_camera),
                                title: Text('Camera'),
                                onTap: () {
                                  _pickImage(ImageSource.camera);
                                  Navigator.of(context).pop();
                                }),
                          ],
                        ),
                      );
                    },
                  );
                },
                child: Container(
                  height: 150,
                  width: 150,
                  decoration:
                      BoxDecoration(border: Border.all(color: Colors.grey)),
                  child: _imageBytes != null
                      ? Image.memory(_imageBytes!, fit: BoxFit.cover)
                      : (_existingImageUrl != null
                          ? Image.network(_existingImageUrl!, fit: BoxFit.cover)
                          : Center(child: Icon(Icons.add_a_photo, size: 50))),
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _field1Controller,
                decoration: InputDecoration(
                  // border: OutlineInputBorder(),
                  labelText: 'Barcode',
                  hintText: widget.product.barcode,
                ),
              ),
              SizedBox(height: 16),
              TextField(
                controller: _field2Controller,
                decoration: InputDecoration(
                  // border: OutlineInputBorder(),
                  labelText: 'Name',
                  hintText: widget.product.name,
                ),
              ),
              SizedBox(height: 16),
              TextField(
                controller: _field3Controller,
                decoration: InputDecoration(
                  // border: OutlineInputBorder(),
                  labelText: 'Cost',
                  hintText: '${widget.product.cost}',
                ),
              ),
              SizedBox(height: 16),
              TextField(
                controller: _field4Controller,
                decoration: InputDecoration(
                  // border: OutlineInputBorder(),
                  labelText: 'Stock',
                  hintText: '${widget.product.stock ?? 'N/A'}',
                ),
              ),
              SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  elevation: 5, // Optional: Customize elevation
                ),
                onPressed: _isUploading ? null : _updateProduct,
                child: _isUploading
                    ? CircularProgressIndicator(color: Colors.white)
                    : Text('Update'),
              ),
            ],
          )),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            // Assign a unique hero tag for the FAB on this screen
            // This part seems to have an issue with async handling.
            // Let's fix it to properly await the result.
            Navigator.push<String>(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const ScannerPage()))
                .then((barcodeScanRes) {
              if (barcodeScanRes != null) {
                _field1Controller.text = barcodeScanRes;
              }
            });
          },
          heroTag: 'updateProductScanFab',
          tooltip: 'Scan QR',
          child: const Icon(Icons.qr_code_scanner_outlined),
        ));
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  _AuthScreenState createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController(text: "raju86g@gmail.com");
  final _passwordController = TextEditingController(text: "123456");
  final _nameController = TextEditingController(text: "Raju G");
  bool _isLogin = true;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _isAppleLoading = false;

  // Google Sign-In instance
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId:
        '396223871595-8qbshb7ohcn03gsc70rjiu5bmppvglc6.apps.googleusercontent.com',
  );

  // Helper to show a snackbar
  void _showError(String message) {
    print("Auth Error: $message");
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  String _hashPassword(String password) {
    final bytes = utf8.encode(password); // data being hashed
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<void> _forgotPassword() async {
    // This would require a more complex implementation (e.g., sending an email with a unique token)
    // and is beyond the scope of this basic custom auth setup.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('Forgot Password is not implemented in this version.')),
    );
  }

  Future<void> _authenticate() async {
    if (_formKey.currentState!.validate()) {
      // Unfocus to prevent web-specific input target errors
      FocusScope.of(context).unfocus();
      setState(() => _isLoading = true);

      try {
        final email = _emailController.text.trim();
        final password = _passwordController.text;
        final usersRef = FirebaseFirestore.instance.collection('users');

        if (_isLogin) {
          // --- LOGIN LOGIC ---
          final querySnapshot =
              await usersRef.where('email', isEqualTo: email).limit(1).get();

          if (querySnapshot.docs.isEmpty) {
            _showError('No user found for that email.');
          } else {
            final userDoc = querySnapshot.docs.first;
            final storedHash = userDoc.data()['passwordHash'];
            final enteredHash = _hashPassword(password);

            if (storedHash == enteredHash) {
              // Passwords match, log in
              final sessionBox = Hive.box('session');
              await sessionBox.put('userId', userDoc.id);
              if (mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (context) => SplashScreen()),
                );
              }
            } else {
              _showError('Wrong password provided.');
            }
          }
        } else {
          // --- SIGNUP LOGIC ---
          final querySnapshot =
              await usersRef.where('email', isEqualTo: email).limit(1).get();

          if (querySnapshot.docs.isNotEmpty) {
            _showError('The account already exists for that email.');
          } else {
            // Create new user
            final passwordHash = _hashPassword(password);
            final newUserDoc = await usersRef.add({
              'name': _nameController.text.trim(),
              'email': email,
              'passwordHash': passwordHash,
              'businessSetupDone': false,
              'createdAt': FieldValue.serverTimestamp(),
            });

            // Log the new user in
            final sessionBox = Hive.box('session');
            await sessionBox.put('userId', newUserDoc.id);

            if (mounted) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (context) => SplashScreen()),
              );
            }
          }
        }
      } catch (e) {
        _showError('An unexpected error occurred: $e');
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_isGoogleLoading) return;
    setState(() => _isGoogleLoading = true);

    UserCredential? userCredential;

    try {
      if (kIsWeb) {
        // Web-specific flow using signInWithPopup
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        googleProvider.setCustomParameters({
          'web-oauth-client-id':
              '396223871595-8qbshb7ohcn03gsc70rjiu5bmppvglc6.apps.googleusercontent.com'
        });
        userCredential =
            await FirebaseAuth.instance.signInWithPopup(googleProvider);
      } else {
        // Mobile-specific flow using google_sign_in package
        final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
        if (googleUser == null) {
          // User canceled the sign-in
          setState(() => _isGoogleLoading = false);
          return;
        }
        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;
        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        userCredential =
            await FirebaseAuth.instance.signInWithCredential(credential);
      }

      if (userCredential.user != null) {
        print('Firebase Auth: Successfully signed in with Google.');
        await _handleSocialSignIn(userCredential.user!);
      }
    } catch (e) {
      // Handle errors for both flows
      print('Google Sign-In Error: $e');
      if (e.toString().contains('popup_closed_by_user')) {
        _showError('Google Sign-In failed. The window was closed.');
      } else {
        _showError('Google Sign-In failed. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGoogleLoading = false;
        });
      }
    }
  }

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }

  Future<void> _signInWithApple() async {
    if (_isAppleLoading) return;
    setState(() => _isAppleLoading = true);

    try {
      final rawNonce = _generateNonce();
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
      );

      final oAuthCredential = OAuthProvider("apple.com").credential(
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
        accessToken: appleCredential.authorizationCode,
      );

      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(oAuthCredential);

      if (userCredential.user != null) {
        await _handleSocialSignIn(userCredential.user!,
            appleCredential.givenName, appleCredential.familyName);
      }
    } catch (e) {
      print('Apple Sign-In Error: $e');
      _showError('Apple Sign-In failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isAppleLoading = false);
      }
    }
  }

  Future<void> _handleSocialSignIn(User user,
      [String? firstName, String? lastName]) async {
    try {
      final usersRef = FirebaseFirestore.instance.collection('users');
      final userDoc = await usersRef.doc(user.uid).get();

      if (!userDoc.exists) {
        // New user, create a document in Firestore
        String displayName = user.displayName ?? '';
        // Construct name from parts if displayName is empty (common with Apple Sign In)
        if (displayName.isEmpty && firstName != null) {
          displayName = firstName + (lastName != null ? ' $lastName' : '');
        }

        await usersRef.doc(user.uid).set({
          'name': displayName.trim(),
          'email': user.email,
          'businessSetupDone': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      // Log the user in by saving their UID
      final sessionBox = Hive.box('session');
      await sessionBox.put('userId', user.uid);

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => SplashScreen()),
        );
      }
    } catch (e) {
      print('Error handling social sign-in: $e');
      _showError('Failed to set up your account. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const SizedBox(height: 40),
              // App Logo/Title
              Text(
                'CartEase',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Color.fromARGB(255, 33, 72, 243),
                  fontFamily: GoogleFonts.poppins().fontFamily,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _isLogin ? 'Welcome back' : 'Create Account',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey[600],
                  fontFamily: GoogleFonts.poppins().fontFamily,
                ),
              ),
              const SizedBox(height: 60),
              // Form
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    if (!_isLogin) ...[
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: 'Full Name',
                          prefixIcon:
                              Icon(Icons.person, color: Colors.grey[400]),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                                color: Color.fromARGB(255, 33, 72, 243)),
                          ),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Enter your name'
                                : null,
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email, color: Colors.grey[400]),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: Color.fromARGB(255, 33, 72, 243)),
                        ),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter your email';
                        }
                        if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                          return 'Enter a valid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock, color: Colors.grey[400]),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: Color.fromARGB(255, 33, 72, 243)),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.length < 6) {
                          return 'Password must be at least 6 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),
                    if (_isLogin) ...[
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _forgotPassword,
                          child: Text(
                            'Forgot Password?',
                            style: TextStyle(
                                color: Color.fromARGB(255, 33, 72, 243)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _authenticate,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color.fromARGB(255, 33, 72, 243),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        child: _isLoading
                            ? SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation(Colors.white),
                                ),
                              )
                            : Text(
                                _isLogin ? 'Sign In' : 'Sign Up',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: GoogleFonts.poppins().fontFamily,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Google Sign In
                    Row(
                      children: [
                        Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text('or continue with',
                              style: TextStyle(color: Colors.grey[500])),
                        ),
                        Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Social Sign-In Buttons
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: _isGoogleLoading ? null : _signInWithGoogle,
                        icon: _isGoogleLoading
                            ? SizedBox(
                                height: 16,
                                width: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(Icons.g_mobiledata,
                                color: Colors.grey[700], size: 20),
                        label: Text(
                          'Google',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[700],
                            fontFamily: GoogleFonts.poppins().fontFamily,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.grey[300]!),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Apple Sign In Button (only on Apple platforms)
                    if (kIsWeb ||
                        Theme.of(context).platform == TargetPlatform.iOS ||
                        Theme.of(context).platform == TargetPlatform.macOS)
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: SignInWithAppleButton(
                          onPressed: _isAppleLoading ? () {} : _signInWithApple,
                          style: Theme.of(context).brightness == Brightness.dark
                              ? SignInWithAppleButtonStyle.white
                              : SignInWithAppleButtonStyle.black,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    const SizedBox(height: 40),
                    // Toggle
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _isLogin
                              ? 'Don\'t have an account? '
                              : 'Already have an account? ',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _isLogin = !_isLogin),
                          child: Text(
                            _isLogin ? 'Sign Up' : 'Sign In',
                            style: TextStyle(
                              color: Color.fromARGB(255, 33, 72, 243),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// BusinessSelectionScreen
class BusinessSelectionScreen extends StatelessWidget {
  final List<DocumentSnapshot> businesses;

  const BusinessSelectionScreen({super.key, required this.businesses});

  Future<void> _selectBusinessAndNavigate(
      BuildContext context, String businessId) async {
    final sessionBox = Hive.box('session');
    sessionBox.put('currentBusinessId', businessId);

    // Load data for the selected business
    final userId = sessionBox.get('userId');
    if (userId != null) {
      // You might want to show a loading indicator here
      final productsSnapshot = await FirebaseFirestore.instance
          .collection('products')
          .where('businessId', isEqualTo: businessId)
          .get();
      products.value = productsSnapshot.docs
          .map((doc) => Product.fromFirestore(doc))
          .toList();

      final invoicesSnapshot = await FirebaseFirestore.instance
          .collection('invoices')
          .where('businessId', isEqualTo: businessId)
          .orderBy('date', descending: true)
          .get();
      invoices.value = invoicesSnapshot.docs
          .map((doc) => Invoice.fromFirestore(doc))
          .toList();
    }
    // Clear the scanned items list to ensure a fresh start
    scannedItems.value.clear();

    // Replace the current screen with the main app screen, ensuring a clean state.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => BottomNavScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Select or Create Business'),
      ),
      body: ListView.builder(
        itemCount: businesses.length,
        itemBuilder: (context, index) {
          final business = businesses[index];
          final businessData = business.data() as Map<String, dynamic>;
          return Card(
            margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              title: Text(businessData['businessName'] ?? 'Unnamed Business'),
              subtitle: Text(businessData['businessType'] ?? ''),
              onTap: () => _selectBusinessAndNavigate(context, business.id),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(context,
              MaterialPageRoute(builder: (context) => BusinessSetupScreen()));
        },
        icon: Icon(Icons.add),
        label: Text('Create New Business'),
      ),
    );
  }
}

// BusinessSetupScreen
class BusinessSetupScreen extends StatefulWidget {
  const BusinessSetupScreen({super.key});

  @override
  _BusinessSetupScreenState createState() => _BusinessSetupScreenState();
}

class _BusinessSetupScreenState extends State<BusinessSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _businessNameController = TextEditingController();
  final _businessTypeController = TextEditingController();
  final _addressController = TextEditingController();

  Future<void> _saveBusinessSetup() async {
    if (_formKey.currentState!.validate()) {
      final sessionBox = Hive.box('session');
      final String? userId = sessionBox.get('userId');
      try {
        if (userId != null) {
          // Create a new business document
          final newBusinessRef =
              await FirebaseFirestore.instance.collection('businesses').add({
            'businessName': _businessNameController.text,
            'businessType': _businessTypeController.text,
            'address': _addressController.text,
            'ownerId': userId,
            'members': [userId], // The creator is the first member
            'createdAt': FieldValue.serverTimestamp(),
          });

          // Set this as the current business
          await sessionBox.put('currentBusinessId', newBusinessRef.id);

          // Navigate to the main app
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => BottomNavScreen()),
            (route) => false,
          );
        }
      } catch (e) {
        print("Business setup failed: ${e.toString()}");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Setup failed: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Business Setup'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextFormField(
                controller: _businessNameController,
                decoration: InputDecoration(labelText: 'Business Name'),
                validator: (value) =>
                    value!.isEmpty ? 'Enter business name' : null,
              ),
              TextFormField(
                controller: _businessTypeController,
                decoration: InputDecoration(labelText: 'Business Type'),
                validator: (value) =>
                    value!.isEmpty ? 'Enter business type' : null,
              ),
              TextFormField(
                controller: _addressController,
                decoration: InputDecoration(labelText: 'Address'),
                validator: (value) => value!.isEmpty ? 'Enter address' : null,
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saveBusinessSetup,
                child: Text('Complete Setup'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// BusinessSettingsScreen - for viewing and updating business settings
class BusinessSettingsScreen extends StatefulWidget {
  const BusinessSettingsScreen({super.key});

  @override
  _BusinessSettingsScreenState createState() => _BusinessSettingsScreenState();
}

class _BusinessSettingsScreenState extends State<BusinessSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _businessNameController = TextEditingController();
  final _businessTypeController = TextEditingController();
  final _addressController = TextEditingController();

  // Currency settings
  final Map<String, String> _currencyMap = {
    'USD': '\$', // US Dollar
    'EUR': '€', // Euro
    'INR': '₹', // Indian Rupee
    'GBP': '£', // British Pound
    'JPY': '¥', // Japanese Yen
    'AUD': 'A\$', // Australian Dollar
    'CAD': 'C\$', // Canadian Dollar
    'CNY': '¥', // Chinese Yuan
    'CHF': 'CHF', // Swiss Franc
    'SGD': 'S\$', // Singapore Dollar
    'NZD': 'NZ\$', // New Zealand Dollar
    'ZAR': 'R', // South African Rand
    'AED': 'د.إ', // UAE Dirham
    'SAR': '﷼', // Saudi Riyal
    'THB': '฿', // Thai Baht
    'KRW': '₩', // South Korean Won
    'RUB': '₽', // Russian Ruble
    'BRL': 'R\$', // Brazilian Real
    'MXN': 'Mex\$', // Mexican Peso
  };

  String? _selectedCurrency;

  // Timezone settings
  final Map<String, String> _timezoneMap = {
    'UTC': 'UTC',
    'America/New_York': 'Eastern Time (ET)',
    'America/Chicago': 'Central Time (CT)',
    'America/Denver': 'Mountain Time (MT)',
    'America/Los_Angeles': 'Pacific Time (PT)',
    'Europe/London': 'London (GMT)',
    'Europe/Paris': 'Paris (CET)',
    'Asia/Kolkata': 'India (IST)',
    'Asia/Tokyo': 'Tokyo (JST)',
    'Australia/Sydney': 'Sydney (AEST)',
  };
  String? _selectedTimezone;

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBusinessData();
  }

  Future<void> _loadBusinessData() async {
    final sessionBox = Hive.box('session');
    final String? businessId = sessionBox.get('currentBusinessId');

    if (businessId != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('businesses')
            .doc(businessId)
            .get();
        if (doc.exists) {
          final data = doc.data();
          setState(() {
            _businessNameController.text = data?['businessName'] ?? '';
            _businessTypeController.text = data?['businessType'] ?? '';
            _addressController.text = data?['address'] ?? '';
            _selectedCurrency = data?['currency'] ?? 'USD';
            _selectedTimezone = data?['timezone'] ?? 'UTC';
            _isLoading = false;
          });
        } else {
          setState(() => _isLoading = false);
        }
      } catch (e) {
        print('Failed to load business data: ${e.toString()}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to load business data: ${e.toString()}')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveBusinessSettings() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      final sessionBox = Hive.box('session');
      final String? businessId = sessionBox.get('currentBusinessId');

      try {
        if (businessId != null) {
          await FirebaseFirestore.instance
              .collection('businesses')
              .doc(businessId)
              .update({
            'businessName': _businessNameController.text.trim(),
            'businessType': _businessTypeController.text.trim(),
            'address': _addressController.text.trim(),
            'currency': _selectedCurrency,
            'timezone': _selectedTimezone ?? 'UTC',
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Business settings updated successfully!')),
          );

          // Navigate back to refresh the drawer
          Navigator.pop(context);
        }
      } catch (e) {
        print('Failed to update settings: ${e.toString()}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update settings: ${e.toString()}')),
        );
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text('Business Settings')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Business Settings'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Update your business information',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 20),
                TextFormField(
                  controller: _businessNameController,
                  decoration: InputDecoration(
                    labelText: 'Business Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      value!.isEmpty ? 'Enter business name' : null,
                ),
                SizedBox(height: 16),
                TextFormField(
                  controller: _businessTypeController,
                  decoration: InputDecoration(
                    labelText: 'Business Type',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      value!.isEmpty ? 'Enter business type' : null,
                ),
                SizedBox(height: 16),
                TextFormField(
                  controller: _addressController,
                  decoration: InputDecoration(
                    labelText: 'Address',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value!.isEmpty ? 'Enter address' : null,
                  maxLines: 3,
                ),
                SizedBox(height: 16),
                Text(
                  'Currency',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedCurrency,
                      hint: Text('Select Currency'),
                      isExpanded: true,
                      items: _currencyMap.entries.map((entry) {
                        return DropdownMenuItem<String>(
                          value: entry.key,
                          child: Text('${entry.key} (${entry.value})'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedCurrency = value;
                        });
                      },
                    ),
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  'Timezone',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedTimezone,
                      hint: Text('Select Timezone'),
                      isExpanded: true,
                      items: _timezoneMap.entries.map((entry) {
                        return DropdownMenuItem<String>(
                          value: entry.key,
                          child: Text('${entry.value} (${entry.key})'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedTimezone = value;
                        });
                      },
                    ),
                  ),
                ),
                SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _saveBusinessSettings,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color.fromARGB(255, 33, 72, 243),
                      foregroundColor: Colors.white,
                    ),
                    child: _isLoading
                        ? CircularProgressIndicator(color: Colors.white)
                        : Text('Update Settings'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _businessTypeController.dispose();
    _addressController.dispose();
    super.dispose();
  }
}

// PaymentSettingsScreen - for viewing and updating business settings
class PaymentSettingsScreen extends StatefulWidget {
  const PaymentSettingsScreen({super.key});

  @override
  _PaymentSettingsScreenState createState() => _PaymentSettingsScreenState();
}

class _PaymentSettingsScreenState extends State<PaymentSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _upiIdController = TextEditingController();
  final _payeeNameController = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPaymentData();
  }

  Future<void> _loadPaymentData() async {
    final sessionBox = Hive.box('session');
    final String? businessId = sessionBox.get('currentBusinessId');

    if (businessId != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('businesses')
            .doc(businessId)
            .get();
        if (doc.exists) {
          final data = doc.data();
          setState(() {
            _upiIdController.text = data?['upiId'] ?? '';
            _payeeNameController.text = data?['payeeName'] ?? '';
            _isLoading = false;
          });
        } else {
          setState(() => _isLoading = false);
        }
      } catch (e) {
        print('Failed to load payment data: ${e.toString()}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to load payment data: ${e.toString()}')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _savePaymentSettings() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      final sessionBox = Hive.box('session');
      final String? businessId = sessionBox.get('currentBusinessId');

      try {
        if (businessId != null) {
          await FirebaseFirestore.instance
              .collection('businesses')
              .doc(businessId)
              .update({
            'upiId': _upiIdController.text.trim(),
            'payeeName': _payeeNameController.text.trim(),
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Payment settings updated successfully!')),
          );
          Navigator.pop(context);
        }
      } catch (e) {
        print('Failed to update payment settings: ${e.toString()}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Failed to update payment settings: ${e.toString()}')),
        );
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  @override
  void dispose() {
    _upiIdController.dispose();
    _payeeNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text('Payment Settings')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Payment Settings'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Configure your UPI payment details',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 20),
                TextFormField(
                  controller: _upiIdController,
                  decoration: InputDecoration(
                    labelText: 'UPI ID (e.g., yourname@bank)',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your UPI ID';
                    }
                    if (!RegExp(r'^[\w.-]+@[\w.-]+$').hasMatch(value)) {
                      return 'Please enter a valid UPI ID';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),
                TextFormField(
                  controller: _payeeNameController,
                  decoration: InputDecoration(
                    labelText: 'Payee Name (Your Name or Business Name)',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      value!.isEmpty ? 'Enter payee name' : null,
                ),
                SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _savePaymentSettings,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color.fromARGB(255, 33, 72, 243),
                      foregroundColor: Colors.white,
                    ),
                    child: _isLoading
                        ? CircularProgressIndicator(color: Colors.white)
                        : Text('Update Payment Settings'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
