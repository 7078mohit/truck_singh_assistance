import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logistics_toolkit/config/config.dart';
import 'package:logistics_toolkit/features/shipment/shipment_preview_page.dart';
import 'address_search_page.dart';
import 'form_step/address_step.dart';
import 'form_step/schedule_step.dart';
import 'form_step/shipment_details_step.dart';
import 'form_step/truck_type_step.dart';
import 'map_picker_page.dart';

final String GOOGLE_MAPS_API_KEY = AppConfig.googleMapsApiKey;

class ShipperFormPage extends StatefulWidget {
  const ShipperFormPage({Key? key}) : super(key: key);

  @override
  _ShipperFormPageState createState() => _ShipperFormPageState();
}

class _ShipperFormPageState extends State<ShipperFormPage>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  final _itemController = TextEditingController();
  final _weightController = TextEditingController();
  final _unitController = TextEditingController();

  final _materialController = TextEditingController();
  final _notesController = TextEditingController();

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  Place? _pickupPlace;
  Place? _dropPlace;

  DateTime? _selectedDate;
  String? _selectedTruckType;
  DateTime? _pickupDate;
  String? _pickupTime;

  String? _selectedShipperId;
  String? _selectedShipperName;
  bool _isLoadingShipper = true;
  bool _isSubmitting = false;
  bool _isPrivate = false;

  int _currentStep = 0;
  final PageController _pageController = PageController();

  List<bool> _stepValid = [false, false, false, false];
  bool _isFormValid = false;

  final List<Map<String, dynamic>> _truckTypes = [
    {'key': 'iconMiniTruck', 'icon': Icons.local_shipping},
    {'key': 'iconPickup', 'icon': Icons.fire_truck},
    {'key': 'iconContainer', 'icon': Icons.inventory_2},
    {'key': 'iconRefrigerated', 'icon': Icons.ac_unit},
    {'key': 'iconFlatbed', 'icon': Icons.crop_16_9},
    {'key': 'iconTanker', 'icon': Icons.local_drink},
    {'key': 'iconTrailer', 'icon': Icons.emoji_transportation},
  ];

  @override
  void initState() {
    super.initState();
    _fetchShippers();
    _loadDraft();
    _initAnimations();
  }

  void _initAnimations() {
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );

    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _itemController.dispose();
    _weightController.dispose();
    _unitController.dispose();
    _materialController.dispose();
    _notesController.dispose();

    _fadeController.dispose();
    _slideController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _fetchShippers() async {
    try {
      var user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      final response = await Supabase.instance.client
          .from('user_profiles')
          .select('custom_user_id, name')
          .eq('user_id', user.id)
          .maybeSingle();
      setState(() {
        _selectedShipperId = response?['custom_user_id'];
        _selectedShipperName = response?['name'];
        _isLoadingShipper = false;
      });
    } catch (e) {
      setState(() => _isLoadingShipper = false);
      debugPrint('Error fetching shipper info: $e');
    }
  }

  Future<void> _loadDraft() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      final pickupDesc = prefs.getString('pickup') ?? '';
      final dropDesc = prefs.getString('drop') ?? '';
      if (pickupDesc.isNotEmpty)
        _pickupPlace = Place(
          description: pickupDesc,
          lat: prefs.getDouble('pickup_latitude') ?? 0,
          lng: prefs.getDouble('pickup_longitude') ?? 0,
        );
      if (dropDesc.isNotEmpty)
        _dropPlace = Place(
          description: dropDesc,
          lat: prefs.getDouble('dropoff_latitude') ?? 0,
          lng: prefs.getDouble('dropoff_longitude') ?? 0,
        );

      _itemController.text = prefs.getString('item') ?? '';
      _weightController.text = prefs.getString('weight') ?? '';
      _unitController.text = prefs.getString('unit') ?? '';
      _materialController.text = prefs.getString('material') ?? '';
      _notesController.text = prefs.getString('notes') ?? '';

      _pickupTime = prefs.getString('pickupTime');
      String? dateString = prefs.getString('deliveryDate');
      if (dateString != null) _selectedDate = DateTime.tryParse(dateString);

      final pickupDateStr = prefs.getString('pickupDate');
      if (pickupDateStr != null) _pickupDate = DateTime.tryParse(pickupDateStr);

      _selectedTruckType = prefs.getString('truckType');
    });

    _validateForm();
  }

  Future<void> _saveDraft() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('pickup', _pickupPlace?.description ?? '');
    await prefs.setString('drop', _dropPlace?.description ?? '');
    await prefs.setString('item', _itemController.text);
    await prefs.setString('weight', _weightController.text);
    await prefs.setString('unit', _unitController.text);
    await prefs.setString('material', _materialController.text);
    await prefs.setString('notes', _notesController.text);

    if (_selectedDate != null)
      await prefs.setString('deliveryDate', _selectedDate!.toIso8601String());
    if (_pickupDate != null)
      await prefs.setString('pickupDate', _pickupDate!.toIso8601String());
    if (_selectedTruckType != null)
      await prefs.setString('truckType', _selectedTruckType!);
    if (_pickupTime != null) await prefs.setString('pickupTime', _pickupTime!);

    if (_pickupPlace != null) {
      await prefs.setDouble('pickup_latitude', _pickupPlace!.lat);
      await prefs.setDouble('pickup_longitude', _pickupPlace!.lng);
    }
    if (_dropPlace != null) {
      await prefs.setDouble('dropoff_latitude', _dropPlace!.lat);
      await prefs.setDouble('dropoff_longitude', _dropPlace!.lng);
    }
  }

  void _validateForm() {
    bool valid = false;
    switch (_currentStep) {
      case 0:
        valid = _selectedTruckType != null;
        break;
      case 1:
        valid =
            _itemController.text.isNotEmpty &&
                _weightController.text.isNotEmpty || _unitController.text.isNotEmpty;
        break;
      case 2:
        valid = _pickupPlace != null && _dropPlace != null;
        break;
      case 3:
        valid =
            _selectedDate != null &&
                _pickupDate != null &&
                _pickupTime != null &&
                _materialController.text.isNotEmpty;
        break;
    }
    setState(() {
      _stepValid[_currentStep] = valid;
      _isFormValid = _stepValid.every((e) => e);
    });
    _saveDraft();
  }

  void _nextStep() {
    if (_currentStep < 3) {
      setState(() {
        _currentStep++;
      });
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
      _resetAnimations();
      _validateForm();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
      _pageController.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
      _resetAnimations();
      _validateForm();
    }
  }

  void _resetAnimations() {
    _fadeController.reset();
    _slideController.reset();
    _fadeController.forward();
    _slideController.forward();
  }

  Future<void> _submitShipment() async {
    if (!_isFormValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please complete all required fields")),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final profile = await Supabase.instance.client
          .from('user_profiles')
          .select('custom_user_id')
          .eq('user_id', userId)
          .maybeSingle();
      final shipperId = profile?['custom_user_id'];

      final today = DateFormat('yyyyMMdd').format(DateTime.now());
      final prefix = 'SHP-$today';

      final response = await Supabase.instance.client
          .from('shipment')
          .select('shipment_id')
          .like('shipment_id', '$prefix%')
          .order('shipment_id', ascending: false)
          .limit(1);

      int newNum = 1;
      if (response.isNotEmpty) {
        final lastId = response.first['shipment_id'] as String;
        final lastNumPart = lastId.split('-').last;
        newNum = (int.tryParse(lastNumPart) ?? 0) + 1;
      }

      final shipmentId = '$prefix-${newNum.toString().padLeft(4, '0')}';

      await Supabase.instance.client.from('shipment').insert({
        'shipment_id': shipmentId,
        'shipper_id': _selectedShipperId,
        'pickup': _pickupPlace!.description,
        'drop': _dropPlace!.description,
        'pickup_latitude': _pickupPlace!.lat,
        'pickup_longitude': _pickupPlace!.lng,
        'dropoff_latitude': _dropPlace!.lat,
        'dropoff_longitude': _dropPlace!.lng,
        'shipping_item': _itemController.text,
        'weight': _weightController.text,
        'unit': _unitController.text,
        'delivery_date': _selectedDate!.toIso8601String(),
        'pickup_date': _pickupDate!.toIso8601String(),
        'material_inside': _materialController.text,
        'truck_type': _selectedTruckType,
        'pickup_time': _pickupTime,
        'notes': _notesController.text,
        'booking_status': _isPrivate ? 'Accepted' : 'Pending',
        'assigned_company': _isPrivate ? shipperId : null,
      });

      await _insertShipmentUpdate(shipmentId);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Submitted successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      _clearForm();

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ShipmentPreviewPage(shipmentId: shipmentId),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Submission failed: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _insertShipmentUpdate(String shipmentId) async {
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      final profile = await supabase
          .from('user_profiles')
          .select('custom_user_id')
          .eq('user_id', userId!)
          .maybeSingle();

      await supabase.from('shipment_updates').insert({
        'shipment_id': shipmentId,
        'notes': 'Initial booking created',
        'updated_by_user_id': profile?['custom_user_id'],
      });
    } catch (e) {
      debugPrint('Error inserting shipment update: $e');
    }
  }

  Future<void> _clearForm() async {
    _formKey.currentState?.reset();
    _itemController.clear();
    _weightController.clear();
    _materialController.clear();
    _unitController.clear();
    _notesController.clear();

    setState(() {
      _pickupPlace = null;
      _dropPlace = null;
      _selectedDate = null;
      _pickupDate = null;
      _pickupTime = null;
      _selectedTruckType = null;
      _currentStep = 0;
      _stepValid = [false, false, false, false];
      _isFormValid = false;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    _pageController.jumpToPage(0);
    _resetAnimations();
  }

  Future<void> _onSearchAddress(bool isPickup) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddressSearchPage()),
    );
    if (result is Place) {
      setState(() {
        if (isPickup)
          _pickupPlace = result;
        else
          _dropPlace = result;
      });
      _validateForm();
    }
  }

  Future<void> _onPickOnMap(bool isPickup) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MapPickerPage()),
    );
    if (result is Place) {
      setState(() {
        if (isPickup)
          _pickupPlace = result;
        else
          _dropPlace = result;
      });
      _validateForm();
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _pickupDate != null
          ? _pickupDate!.add(const Duration(days: 1))
          : DateTime.now().add(const Duration(days: 1)),
      firstDate: _pickupDate ?? DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _validateForm();
    }
  }

  Future<void> _pickPickupDate() async {
    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a delivery date first.')),
      );
      return;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: _selectedDate!,
    );
    if (picked != null) {
      setState(() => _pickupDate = picked);
      _validateForm();
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        _pickupTime = picked.format(context);
      });
      _validateForm();
    }
  }

  Widget _buildProgressBar() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Container(
          padding: const EdgeInsets.all(20),
          margin: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            //color: Colors.white,
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              BoxShadow(
                //color: Colors.grey.withOpacity(0.1),
                color: Theme.of(context).shadowColor.withValues(alpha: 0.1),
                spreadRadius: 2,
                blurRadius: 10,
                offset: const Offset(0, 3),
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
                    'Step ${_currentStep + 1} of 4',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      //color: Colors.black87,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _saveDraft,
                    icon: const Icon(Icons.save, size: 18),
                    label: const Text('Save Draft'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.orange,
                      //backgroundColor: Colors.orange.shade50,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: List.generate(
                  4,
                      (index) => Expanded(
                    child: Container(
                      height: 8,
                      margin: EdgeInsets.only(right: index < 3 ? 4 : 0),
                      decoration: BoxDecoration(
                        color: index <= _currentStep
                            ? Colors.orange
                            : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _stepDescription(),
                style: const TextStyle(/*color: Colors.grey,*/ fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _stepDescription() {
    switch (_currentStep) {
      case 0:
        return 'Choose your preferred truck type';
      case 1:
        return 'Enter shipment details';
      case 2:
        return 'Set pickup and delivery locations';
      case 3:
        return 'Schedule and preferences';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      //backgroundColor: Colors.grey.shade50,
      // appBar: CustomAppBar(
      //   pageTitle: 'Create Shipment',
      //   showProfile: false,
      //   showNotifications: false,
      // ),
      appBar: AppBar(title: Text('createShipment'.tr())),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            onChanged: _validateForm,
            child: Column(
              children: [
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      TruckTypeStep(
                        truckTypes: _truckTypes,
                        selectedTruckType: _selectedTruckType,
                        onTruckTypeSelected: (val) {
                          setState(() {
                            _selectedTruckType = val;
                          });
                          _validateForm();
                        },
                        progressBar: _buildProgressBar(),
                        shipperName: _selectedShipperName,
                        isLoadingShipper: _isLoadingShipper,
                      ),
                      ShipmentDetailsStep(
                        itemController: _itemController,
                        weightController: _weightController,
                        unitController: _unitController,
                        onChanged: _validateForm,
                        progressBar: _buildProgressBar(),
                      ),
                      AddressStep(
                        pickupPlace: _pickupPlace,
                        dropPlace: _dropPlace,
                        onPickupSearch: () => _onSearchAddress(true),
                        onDropSearch: () => _onSearchAddress(false),
                        onPickupMapPick: () => _onPickOnMap(true),
                        onDropMapPick: () => _onPickOnMap(false),
                        progressBar: _buildProgressBar(),
                      ),
                      ScheduleStep(
                        selectedDate: _selectedDate,
                        pickupTime: _pickupTime,
                        pickupDate: _pickupDate,
                        materialController: _materialController,
                        notesController: _notesController,
                        isPrivate: _isPrivate,
                        onDatePick: _pickDate,
                        onPickupDatePick: _pickPickupDate,
                        onTimePick: _pickTime,
                        onPrivateChanged: (v) {
                          setState(() {
                            _isPrivate = v ?? false;
                          });
                        },
                        onChanged: _validateForm,
                        progressBar: _buildProgressBar(),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    children: [
                      if (_currentStep > 0)
                        Expanded(
                          flex: 1,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              FocusScope.of(context).unfocus();
                              _previousStep();
                            },
                            icon: const Icon(Icons.arrow_back, size: 18),
                            label: const Text('Back'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey.shade600,
                              //foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        )
                      else
                        const Expanded(flex: 1, child: SizedBox()),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: _currentStep == 3
                            ? ElevatedButton.icon(
                          onPressed: _isFormValid && !_isSubmitting
                              ? () {
                            FocusScope.of(context).unfocus();
                            _submitShipment();
                          }
                              : null,
                          icon: _isSubmitting
                              ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              //color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                              : const Icon(Icons.send, size: 18),
                          label: Text(
                            _isSubmitting ? 'Submitting...' : 'Submit',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                            _isFormValid && !_isSubmitting
                                ? Colors.green.shade600
                                : Colors.grey.shade400,
                            //foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              vertical: 18,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        )
                            : ElevatedButton.icon(
                          onPressed: _stepValid[_currentStep]
                              ? () {
                            FocusScope.of(context).unfocus();
                            _nextStep();
                          }
                              : null,
                          icon: const Icon(Icons.arrow_forward, size: 18),
                          label: const Text('Next'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _stepValid[_currentStep]
                                ? Colors.orange.shade600
                                : Colors.grey.shade400,
                            //foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              vertical: 18,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
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
}