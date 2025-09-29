import 'package:flutter/material.dart';
// import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:cartease/scanner.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui' as ui;
import 'dart:convert'; // For utf8 encoding
import 'package:crypto/crypto.dart'; // For password hashing
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// Import the generated file
import 'firebase_options.dart';

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

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(Hive.box('settings').get('isDarkMode', defaultValue: false) ? ThemeMode.dark : ThemeMode.light);

class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
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
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => AuthScreen()));
    } else {
      // A user is logged in, verify their setup status
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
        if (!mounted) return;

        final data = doc.data();
        final isBusinessSetupDone = data != null && data['businessSetupDone'] == true;

        if (isBusinessSetupDone) {
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => BottomNavScreen()));
        } else {
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => BusinessSetupScreen()));
        }
      } catch (e) {
        print("Error checking auth status: $e");
        // If something goes wrong (e.g., user deleted), log them out.
        sessionBox.delete('userId');
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => AuthScreen()));
      }
    }
    _loadUserData(userId);
  }

  Future<void> _loadUserData(String? userId) async {
    if (userId == null) return;

    try {
      // Load Products
      final productsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('products')
          .get();
      final userProducts = productsSnapshot.docs
          .map((doc) => Product.fromFirestore(doc))
          .toList();
      products.value = userProducts;

      // Load Invoices
      final invoicesSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('invoices')
          .orderBy('date', descending: true)
          .get();
      final userInvoices = invoicesSnapshot.docs
          .map((doc) => Invoice.fromFirestore(doc))
          .toList();
      invoices = userInvoices;
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
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, ThemeMode currentMode, __) {
        // Determine the user's locale for currency formatting.
        Locale systemLocale = ui.window.locale;
        String countryCode = systemLocale.countryCode ?? "US"; // Default to "US" if null

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
              background: Color(0xFFFAFAFA),
              error: Colors.red,
              onPrimary: Colors.white,
              onSecondary: Colors.white,
              onSurface: Colors.black87,
              onBackground: Colors.black87,
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
            appBarTheme: AppBarTheme(color: Color.fromARGB(255, 27, 27, 27)),
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

  ScannedItem({required this.name, required this.cost});

  // Method to convert a ScannedItem to a map for Firestore
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'cost': cost,
    };
  }

  // Factory constructor to create a ScannedItem from a map
  factory ScannedItem.fromMap(Map<String, dynamic> map) {
    return ScannedItem(name: map['name'] ?? '', cost: (map['cost'] ?? 0.0).toDouble());
  }
}

class Product {
  final String? id;
  final String barcode;
  final String name;
  final double cost; // This should be double
  final DateTime date;

  Product({
    this.id,
    required this.barcode,
    required this.name,
    required this.cost,
    required this.date,
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
    );
  }

  // Method to convert a Product to a map for Firestore
  Map<String, dynamic> toJson() {
    return {
      'barcode': barcode,
      'name': name,
      'cost': cost,
      'date': Timestamp.fromDate(date),
    };
  }
}

// Model for Invoice
class Invoice {
  final String? id; // Optional: To store the Firestore document ID
  final List<ScannedItem> items;
  final double totalAmount;
  final DateTime date;

  Invoice({this.id, required this.items, required this.totalAmount, required this.date});

  // Method to convert an Invoice to a map for Firestore
  Map<String, dynamic> toJson() {
    return {
      'items': items.map((item) => item.toJson()).toList(),
      'totalAmount': totalAmount,
      'date': Timestamp.fromDate(date),
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
      items: invoiceItems,
      totalAmount: (data['totalAmount'] ?? 0.0).toDouble(),
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
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
List<Invoice> invoices = [];
String? userCurrencySymbol; // Global variable for the user's currency symbol
//List<Product> products = [];

// Main Screen with Bottom Navigation
class BottomNavScreen extends StatefulWidget {
  @override
  _BottomNavScreenState createState() => _BottomNavScreenState();
}

int _selectedIndex = 0;

class _BottomNavScreenState extends State<BottomNavScreen> {
  // List of screens to navigate between
  final List<Widget> _screens = [
    DashboardScreen(),
    ScannedListScreen(),
    InvoiceListScreen(),
  ];

  Future<DocumentSnapshot> _getUserBusinessData() async {
    final sessionBox = Hive.box('session');
    final String? userId = sessionBox.get('userId');

    if (userId != null) {
      // Also load the currency symbol for the drawer
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>?;
          final currencyCode = data?['currency'];
          if (currencyCode != null) {
            final Map<String, String> currencyMap = {'USD': '\$', 'EUR': '€', 'INR': '₹', 'GBP': '£', 'JPY': '¥'};
            userCurrencySymbol = currencyMap[currencyCode];
          }
        }
      } catch (e) {
        print("Failed to load user currency for drawer: $e");
      }

      return await FirebaseFirestore.instance.collection('users').doc(userId).get();
    } else {
      // Return a dummy document snapshot if no user is logged in
      return FirebaseFirestore.instance.collection('users').doc('dummy').get();
    }
  }

  Future<void> _logout() async {
    final sessionBox = Hive.box('session');
    await sessionBox.delete('userId');

    // ** CRITICAL: Clear all global data on logout **
    products.value = [];
    scannedItems.value = [];
    invoices.clear();

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
            'CartEase',
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
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              FutureBuilder<DocumentSnapshot>(
                future: _getUserBusinessData(),
                builder: (context, snapshot) {
                  String businessName = 'CartEase';
                  String businessType = '';

                  if (snapshot.hasData && snapshot.data != null) {
                    final data = snapshot.data!.data() as Map<String, dynamic>?;
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
                    MaterialPageRoute(builder: (context) => UserProfileForm()),
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
                    MaterialPageRoute(builder: (context) => BusinessSettingsScreen()),
                  );
                },
              ),
              Divider(),
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
              BottomNavigationBarItem(
                  icon: Icon(Icons.list), label: "Scanned List"),
              BottomNavigationBarItem(
                  icon: Icon(Icons.receipt), label: "Invoices"),
            ],
            selectedItemColor: Colors.white, // Selected item text color
            unselectedItemColor:
                Colors.white.withOpacity(0.3), // Unselected item text color
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: scanBarcode,
          tooltip: 'Scan QR',
          child: Icon(Icons.qr_code_scanner_outlined),
        ));
  }

  // Function to scan barcode (same as before)
  Future<void> scanBarcode() async {
    final barcodeScanRes = await Navigator.push<String>(
        context, MaterialPageRoute(builder: (context) => const ScannerPage()));

    setState(() {
      if (barcodeScanRes != null) {
        if (products.value != null && products.value.length > 0) {
          Product? matchedProduct = products.value.firstWhere(
            (aProduct) => aProduct.barcode == barcodeScanRes,
          );

          if (matchedProduct != null) {
            scannedItems.value = List.from(scannedItems.value)
              ..add(ScannedItem(
                  name: matchedProduct != null ? matchedProduct.name : 'Sample',
                  cost: matchedProduct != null ? matchedProduct.cost : 10));

            // addCost(matchedProduct != null ? matchedProduct.cost : 10);
          } else {
            scannedItems.value = List.from(scannedItems.value)
              ..add(ScannedItem(name: 'Sample', cost: 10));
            // addCost(10);
          }
        } else {
          scannedItems.value = List.from(scannedItems.value)
            ..add(ScannedItem(name: '$barcodeScanRes', cost: 10));
          // addCost(10);
        }
      } else {
        scannedItems.value = List.from(scannedItems.value)
          ..add(ScannedItem(name: 'Sample', cost: 10));
        // addCost(10);
      }
      _selectedIndex = 1; // Switch to ScannedListScreen tab
    });
  }
}

// Method to get formatted currency symbol
String getCurrencySymbol(BuildContext context) {
  Locale locale = Localizations.localeOf(context);
  return NumberFormat.simpleCurrency(locale: locale.toString()).currencySymbol;
}

// Method to get currency icon based on symbol
IconData getCurrencyIcon(String currencySymbol) {
  switch (currencySymbol) {
    case '\$':
      return Icons.attach_money; // Dollar symbol
    case '€':
      return Icons.euro; // Euro symbol
    case '£':
      return Icons.currency_pound; // Pound symbol
    case '₹':
      return Icons.currency_rupee; // Rupee symbol
    case '¥':
      return Icons.currency_yen; // Yen symbol
    default:
      return Icons.monetization_on; // General currency icon
  }
}

// Dashboard Screen (Home Screen)
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  double calculateTotalAmount(List<Invoice> invoices) {
    return invoices.fold(0.0, (sum, invoice) => sum + invoice.totalAmount);
  }

  Map<int, double> getMonthlySales() {
    Map<int, double> monthly = {};
    for (var invoice in invoices) {
      int month = invoice.date.month;
      monthly[month] = (monthly[month] ?? 0) + invoice.totalAmount;
    }
    return monthly;
  }

  Map<int, int> getMonthlyOrders() {
    Map<int, int> monthly = {};
    for (var invoice in invoices) {
      int month = invoice.date.month;
      monthly[month] = (monthly[month] ?? 0) + 1;
    }
    return monthly;
  }

  Map<int, double> getCumulativeSales() {
    Map<int, double> monthly = getMonthlySales();
    Map<int, double> cumulative = {};
    double sum = 0;
    for (int m = 1; m <= 12; m++) {
      sum += monthly[m] ?? 0;
      cumulative[m] = sum;
    }
    return cumulative;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
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
                // Metrics Cards - Made scrollable for smaller screens
                SizedBox(
                  height: 150,
                  width: double.infinity,
                  child: ListView(
                    // Changed to ListView for horizontal scrolling
                    scrollDirection: Axis.horizontal,
                    children: [
                      _buildMetricCard(
                        context: context,
                        icon: getCurrencyIcon(userCurrencySymbol ?? getCurrencySymbol(context)),
                        value:
                            '${calculateTotalAmount(invoices).toStringAsFixed(2)}',
                        label: 'Revenue',
                        color: Theme.of(context).colorScheme.primary, // Use primary color for consistency
                      ),
                      const SizedBox(width: 12),
                      _buildMetricCard(
                        context: context,
                        icon: Icons.shopping_cart,
                        value: '${invoices.length}',
                        label: 'Orders',
                        color: Colors.blue,
                      ), // Consider using theme colors here too
                      const SizedBox(width: 12),
                      _buildMetricCard(
                        context: context,
                        icon: Icons.person,
                        value: '${invoices.length}',
                        label: 'Customers',
                        color: Theme.of(context).colorScheme.secondary, // Use secondary color for consistency
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Sales Overview Chart - Adjusted height
                Container(
                  height: 250, // Reduced height
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
                      Text(
                        'Sales Overview',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
                                      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                                      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
                                    ];
                                    if (value.toInt() >= 0 && value.toInt() < months.length) {
                                      return Text( // Use theme's text style
                                        months[value.toInt()],
                                        style: TextStyle(
                                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
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

                // Bottom Charts - Made scrollable
                SizedBox(
                  height: 200,
                  child: ListView(
                    // Changed to ListView for horizontal scrolling
                    scrollDirection: Axis.horizontal,
                    children: [
                      SizedBox(
                        width: 200,
                        child:
                            _buildActivityChart(context, 'Performance', Theme.of(context).colorScheme.primary),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 200,
                        child: _buildActivityChart(context, 'Conversion', Theme.of(context).colorScheme.secondary),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 200,
                        child: _buildActivityChart(context, 'Growth', Colors.teal), // Using a different color
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActivityChart(BuildContext context, String title, Color color) {
    // For simplicity, use monthly orders for bar charts
    List<BarChartGroupData> barGroups = [];
    Map<int, int> monthlyOrders = getMonthlyOrders();
    double maxOrders = monthlyOrders.values.isNotEmpty ? monthlyOrders.values.reduce((a, b) => a > b ? a : b).toDouble() : 20;
    for (int i = 0; i < 5; i++) { // Last 5 months
      int month = DateTime.now().month - 4 + i; // Adjust for current month
      if (month < 1) month += 12;
      int orders = monthlyOrders[month] ?? 0;
      barGroups.add(BarChartGroupData(
        x: i,
        barRods: [BarChartRodData(toY: orders.toDouble(), color: color)],
      ));
    }

    return Container(
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
          Text(
            title, // Use theme's text style
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxOrders * 1.2,
                barTouchData: BarTouchData(enabled: false),
                titlesData: FlTitlesData(
                  show: true,
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
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                gridData: FlGridData(show: false),
                barGroups: barGroups,
              ),
            ),
          ),
        ],
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
      decoration: BoxDecoration( // Use theme's card color
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
          Text( // Use theme's text style
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
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

  // Variable to store the selected currency
  String? _selectedCurrency;

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
        DocumentSnapshot doc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
        if (doc.exists) {
          setState(() {
            _selectedCurrency = doc.get('currency');
          });
        }
      }
    } catch (e) {
      print('Failed to load currency: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    isButtonEnabled = scannedItems.value.length > 0;

    return Scaffold(
      appBar: AppBar(
        title: Text('Scanned Items'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ValueListenableBuilder<List<ScannedItem>>(
              valueListenable: scannedItems,
              builder: (context, items, _) {
                if (items.isEmpty) {
                  return Center(
                    child: Text(
                      'No items scanned yet.',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 16),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ListTile(
                      tileColor: index % 2 == 0 ? Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3) : Colors.transparent,
                      title: Text(
                        item.name,
                        style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${userCurrencySymbol ?? getCurrencySymbol(context)}${item.cost.toStringAsFixed(2)}',
                            style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
                            onPressed: () => _deleteItem(index),
                            padding: EdgeInsets.only(left: 25.0),
                            hoverColor: Colors.transparent,
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                SizedBox(height: 10),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    elevation: 5, // Optional: Customize elevation
                  ),
                  onPressed: () {
                    // Navigate to payment screen
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            PaymentScreen(totalAmount: calculateTotalAmount()),
                      ),
                    );
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text("Pay Now",
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
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

// Payment Screen
class PaymentScreen extends StatelessWidget {
  final double totalAmount;

  const PaymentScreen({super.key, required this.totalAmount});

  @override
  Widget build(BuildContext context) {
    // Example UPI details for QR code
    String upiUrl =
        'upi://pay?pa=your-upi-id@bank&pn=Your Name&am=${totalAmount.toStringAsFixed(2)}&cu=INR';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pay Now'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Scan this QR code to pay',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
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
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                SizedBox(width: 5),
                Icon(
                  getCurrencyIcon(getCurrencySymbol(context)),
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                Text(totalAmount.toStringAsFixed(2),
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
              ],
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                elevation: 5, // Optional: Customize elevation
              ),
              onPressed: () {
                completePayment(context);
                // Navigator.of(context).pushNamed("/ScannedListScreen");
                Navigator.pop(context);

                // Navigator.push(
                //     // Navigate to the next screen
                //     context,
                //     MaterialPageRoute(
                //         builder: (context) => InvoiceListScreen()));
              },
              child: Text('OK'),
            ),
          ],
        ),
      ),
    );
  }

  // Function to complete payment and create invoice
  Future<void> completePayment(BuildContext context) async {
    if (scannedItems.value.isEmpty) return;

    final sessionBox = Hive.box('session');
    final String? userId = sessionBox.get('userId');

    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: Not logged in.")));
      return;
    }

    try {
      // Create a new invoice object
      Invoice newInvoice = Invoice(
        items: List.from(scannedItems.value),
        totalAmount: totalAmount,
        date: DateTime.now(),
      );

      // Save the new invoice to Firestore
      final docRef = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('invoices')
          .add(newInvoice.toJson());

      // Add to local list and clear scanned items
      invoices.insert(0, Invoice.fromFirestore(await docRef.get())); // Add to start of list
      scannedItems.value = []; // Clear the cart

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Payment successful! Invoice created.')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save invoice: $e')));
    }
  }
}

// Invoice List Screen
class InvoiceListScreen extends StatefulWidget {
  @override
  _InvoiceListScreenState createState() => _InvoiceListScreenState();
}

class _InvoiceListScreenState extends State<InvoiceListScreen> {
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadInvoices();
  }

  Future<void> _loadInvoices() async {
    setState(() => _isLoading = true);

    final sessionBox = Hive.box('session');
    final String? userId = sessionBox.get('userId');

    if (userId != null) {
      try {
        final querySnapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('invoices')
            .orderBy('date', descending: true)
            .get();

        final loadedInvoices = querySnapshot.docs
            .map((doc) => Invoice.fromFirestore(doc))
            .toList();

        setState(() {
          invoices.clear();
          invoices.addAll(loadedInvoices);
        });
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load invoices: $e')),
        );
      }
    }

    setState(() => _isLoading = false);
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Invoices'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadInvoices,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : invoices.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.receipt_long, size: 64, color: Theme.of(context).colorScheme.outline),
                      SizedBox(height: 16),
                      Text(
                        'No invoices yet',
                        style: TextStyle(fontSize: 18, color: Theme.of(context).colorScheme.onSurface),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Create your first invoice by scanning items and completing payment',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: invoices.length,
                  itemBuilder: (context, index) {
                    final invoice = invoices[index];
                    return Card(
                      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: ListTile(
                        tileColor: index % 2 == 0 ? Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.2) : Theme.of(context).cardColor,
                        title: Text(
                          'Invoice #${index + 1}',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                        ),
                        subtitle: Text(
                          'Date: ${invoice.date.toString().split(' ')[0]}',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              invoice.totalAmount.toStringAsFixed(2),
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
                              builder: (context) => InvoiceDetailScreen(invoice: invoice),
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

  InvoiceDetailScreen({required this.invoice});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Invoice Details'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Date: ${invoice.date}', style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface)),
            SizedBox(height: 16),
            Text('Items:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
            Expanded(
              child: ListView.builder(
                itemCount: invoice.items.length,
                itemBuilder: (context, index) {
                  final item = invoice.items[index];
                  return ListTile(
                    tileColor: index % 2 == 0 ? Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.2) : Colors.transparent,
                    title: Text(item.name, style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface)),
                    trailing: Text('${userCurrencySymbol ?? getCurrencySymbol(context)}${item.cost.toStringAsFixed(2)}', style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface)),
                  );
                },
              ),
            ),
            SizedBox(height: 16),
            Text('Total: ${userCurrencySymbol ?? getCurrencySymbol(context)}${invoice.totalAmount.toStringAsFixed(2)}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
          ],
        ),
      ),
    );
  }
}

class UserProfileForm extends StatefulWidget {
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
        DocumentSnapshot doc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
        if (doc.exists) {
          setState(() {
            _nameController.text = doc.get('name') ?? '';
            _emailController.text = doc.get('email') ?? '';
            _phoneController.text = doc.get('phone') ?? '';
          });
        }
      }
    } catch (e) {
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
        await FirebaseFirestore.instance.collection('users').doc(userId).update({
          'name': _nameController.text.trim(),
          'email': _emailController.text.trim(),
          'phone': _phoneController.text.trim(),
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Profile Updated and Saved Successfully')),
        );
      }
    } catch (e) {
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
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
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
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
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
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
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
  const AddProductScreen({super.key});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final TextEditingController _field1Controller = TextEditingController();
  final TextEditingController _field2Controller = TextEditingController();
  final TextEditingController _field3Controller = TextEditingController();

  @override
  void dispose() {
    _field1Controller.dispose();
    _field2Controller.dispose();
    _field3Controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: Text('Add Product')),
        body: Padding(
          padding: const EdgeInsets.all(50.0),
          child: Column(
            children: [
              TextField(
                controller: _field1Controller,
                decoration: InputDecoration(labelText: 'Barcode'),
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
              SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  elevation: 5, // Optional: Customize elevation
                ),
                onPressed: () {
                  final newProduct = Product(
                    barcode: _field1Controller.text,
                    name: _field2Controller.text,
                    cost: double.tryParse(_field3Controller.text) ?? 0.0,
                    date: DateTime.now(),
                  );
                  _saveProductToFirestore(newProduct);
                },
                child: Text('Save',
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
          tooltip: 'Scan QR',
          child: Icon(Icons.qr_code_scanner_outlined),
        ));
  }

  Future<void> _saveProductToFirestore(Product product) async {
    final sessionBox = Hive.box('session');
    final String? userId = sessionBox.get('userId');
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Not logged in.")));
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('users').doc(userId).collection('products').add(product.toJson());
      products.value = [...products.value, product]; // Update local list
      Navigator.pop(context); // Go back after saving
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to save product: $e")));
    }
  }

  Future<void> addBarcode() async {
    final barcodeScanRes = await Navigator.push<String>(
        context, MaterialPageRoute(builder: (context) => const ScannerPage()));

    if (barcodeScanRes != null) {
      _field1Controller.text = '$barcodeScanRes';
      _field3Controller.text = 50.toString();
    } else {
      _field1Controller.text = '123456';
      _field3Controller.text = 5.toString();
    }
    setState(() {});
  }
}

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  Future<void> _deleteItem(int index) async {
    final productToDelete = products.value[index];
    final productId = productToDelete.id;

    if (productId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: Cannot delete product without an ID.")),
      );
      return;
    }

    final sessionBox = Hive.box('session');
    final String? userId = sessionBox.get('userId');

    try {
      // Delete from Firestore
      await FirebaseFirestore.instance.collection('users').doc(userId).collection('products').doc(productId).delete();

      // Update local state
      products.value = List.from(products.value)..removeAt(index);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to delete product: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Products'),
      ),
      body: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start, // Align the content to the top
        children: [
          Expanded(
            child: ValueListenableBuilder<List<Product>>(
              valueListenable: products,
              builder: (context, items, _) {
                // calculateTotal();
                // Calculate widths based on screen width
                // double nameColumnWidth =
                //     constraints.maxWidth * 0.3; // 30% width
                // double ageColumnWidth = constraints.maxWidth * 0.2; // 20% width
                // double occupationColumnWidth =
                //     constraints.maxWidth * 0.5; // 50% width
                return Column(
                    crossAxisAlignment: CrossAxisAlignment
                        .start, // Align the content to the top
                    children: [
                      SizedBox(
                          width: double
                              .infinity, // Take the full width of the screen
                          child: DataTable(
                            columns: [
                              DataColumn(
                                  label: SizedBox(
                                child: Text(
                                  "Barcode",
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              )),
                              DataColumn(
                                  label: SizedBox(
                                child: Text("Name",
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                              )),
                              DataColumn(
                                  label: SizedBox(
                                child: Text("Cost",
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                              )),
                              DataColumn(
                                  label: SizedBox(
                                // Set a specific width for this column
                                child: Text(""),
                              )),
                            ],
                            rows: List.generate(
                              items.length,
                              (index) => DataRow(
                                color:
                                    MaterialStateProperty.resolveWith<Color?>(
                                  (Set<MaterialState> states) {
                                    return index % 2 == 0
                                        ? Colors.grey.withOpacity(0.2)
                                        : Colors.white.withOpacity(0.1);
                                  },
                                ),
                                cells: [
                                  DataCell(SizedBox(
                                    child: Text(items[index].barcode),
                                  )),
                                  DataCell(
                                    SizedBox(child: Text(items[index].name)),
                                  ),
                                  DataCell(SizedBox(
                                    child: Text(
                                        '${userCurrencySymbol ?? getCurrencySymbol(context)}${items[index].cost.toStringAsFixed(2)}'),
                                  )),
                                  DataCell(IconButton(
                                    icon: Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => _deleteItem(index),
                                  )),
                                ],
                              ),
                            ),
                          ))
                    ]);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ProductDetailScreen extends StatelessWidget {
  final Product product;
  final TextEditingController _field1Controller = TextEditingController();
  final TextEditingController _field2Controller = TextEditingController();
  final TextEditingController _field3Controller = TextEditingController();

  @override
  void dispose() {
    _field1Controller.dispose();
    _field2Controller.dispose();
    _field3Controller.dispose();
    // super.dispose();
  }

  ProductDetailScreen({required this.product});

  @override
  Widget build(BuildContext context) {
    _field1Controller.text = product.barcode;
    _field2Controller.text = product.name;
    _field3Controller.text = product.cost.toString();
    return Scaffold(
        appBar: AppBar(title: Text('Update Product')),
        body: Padding(
          padding: const EdgeInsets.all(50.0),
          child: Column(
            children: [
              TextField(
                controller: _field1Controller,
                decoration: InputDecoration(
                  // border: OutlineInputBorder(),
                  labelText: 'Barcode',
                  hintText: '${product.barcode}',
                ),
              ),
              SizedBox(height: 16),
              TextField(
                controller: _field2Controller,
                decoration: InputDecoration(
                  // border: OutlineInputBorder(),
                  labelText: 'Name',
                  hintText: '${product.name}',
                ),
              ),
              SizedBox(height: 16),
              TextField(
                controller: _field3Controller,
                decoration: InputDecoration(
                  // border: OutlineInputBorder(),
                  labelText: 'Cost',
                  hintText: '${product.cost}',
                ),
              ),
              SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  elevation: 5, // Optional: Customize elevation
                ),
                onPressed: () {
                  products.value.removeWhere(
                      (aProduct) => aProduct.barcode == product.barcode);

                  products.value.add(Product(
                    barcode: _field1Controller.text,
                    name: _field2Controller.text,
                    cost: double.parse(_field3Controller.text),
                    date: DateTime.now(),
                  ));
                  Navigator.pop(context);
                },
                child: Text('Update'),
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            final barcodeScanRes = Navigator.push<String>(context,
                MaterialPageRoute(builder: (context) => const ScannerPage()));

            if (barcodeScanRes != null) {
              print(barcodeScanRes);
              _field1Controller.text = barcodeScanRes.toString();
              _field3Controller.text = 50.toString();
            }
          },
          tooltip: 'Scan QR',
          child: Icon(Icons.qr_code_scanner_outlined),
        ));
  }
}

class AuthScreen extends StatefulWidget {
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

  // Helper to show a snackbar
  void _showError(String message) {
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
          final querySnapshot = await usersRef.where('email', isEqualTo: email).limit(1).get();

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
          final querySnapshot = await usersRef.where('email', isEqualTo: email).limit(1).get();

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

  Future<void> _forgotPassword() async {
    // This would require a more complex implementation (e.g., sending an email with a unique token)
    // and is beyond the scope of this basic custom auth setup.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Forgot Password is not implemented in this version.')),
    );
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
                          prefixIcon: Icon(Icons.person, color: Colors.grey[400]),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Color.fromARGB(255, 33, 72, 243)),
                          ),
                        ),
                        validator: (value) => value == null || value.trim().isEmpty ? 'Enter your name' : null,
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
                          borderSide: BorderSide(color: Color.fromARGB(255, 33, 72, 243)),
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
                          borderSide: BorderSide(color: Color.fromARGB(255, 33, 72, 243)),
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
                            style: TextStyle(color: Color.fromARGB(255, 33, 72, 243)),
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
                                  valueColor: AlwaysStoppedAnimation(Colors.white),
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
                    // Google Sign In (Placeholder - add google_sign_in package if needed)
                    Row(
                      children: [
                        Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text('or continue with', style: TextStyle(color: Colors.grey[500])),
                        ),
                        Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: null, // Google Sign-In is removed
                        icon: Icon(Icons.g_mobiledata, color: Colors.grey[700], size: 20),
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
                    const SizedBox(height: 40),
                    // Toggle
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _isLogin ? 'Don\'t have an account? ' : 'Already have an account? ',
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

// BusinessSetupScreen
class BusinessSetupScreen extends StatefulWidget {
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
          await FirebaseFirestore.instance.collection('users').doc(userId).update({
            'businessName': _businessNameController.text,
            'businessType': _businessTypeController.text,
            'address': _addressController.text,
            'businessSetupDone': true,
          });
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => BottomNavScreen()),
          );
        }
      } catch (e) {
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
                validator: (value) => value!.isEmpty ? 'Enter business name' : null,
              ),
              TextFormField(
                controller: _businessTypeController,
                decoration: InputDecoration(labelText: 'Business Type'),
                validator: (value) => value!.isEmpty ? 'Enter business type' : null,
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
    'USD': '\$',
    'EUR': '€',
    'INR': '₹',
    'GBP': '£',
    'JPY': '¥',
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
    final String? userId = sessionBox.get('userId');

    if (userId != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>?;
          setState(() {
            _businessNameController.text = data?['businessName'] ?? '';
            _businessTypeController.text = data?['businessType'] ?? '';
            _addressController.text = data?['address'] ?? '';
            _selectedCurrency = data?['currency'];
            _selectedTimezone = data?['timezone'] ?? 'UTC';
            _isLoading = false;
          });
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load business data: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveBusinessSettings() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      final sessionBox = Hive.box('session');
      final String? userId = sessionBox.get('userId');

      try {
        if (userId != null) {
          await FirebaseFirestore.instance.collection('users').doc(userId).update({
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update settings: $e')),
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
                  validator: (value) => value!.isEmpty ? 'Enter business name' : null,
                ),
                SizedBox(height: 16),
                TextFormField(
                  controller: _businessTypeController,
                  decoration: InputDecoration(
                    labelText: 'Business Type',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value!.isEmpty ? 'Enter business type' : null,
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
