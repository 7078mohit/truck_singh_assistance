import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

class CompanyDriverEmergencyScreen extends StatefulWidget {
  final String agentId;
  const CompanyDriverEmergencyScreen({super.key, required this.agentId});
  @override
  State<CompanyDriverEmergencyScreen> createState() =>
      _CompanyDriverEmergencyScreenState();
}

class _CompanyDriverEmergencyScreenState
    extends State<CompanyDriverEmergencyScreen> {
  final TextEditingController messageController = TextEditingController();
  final List<String> helpOptions = [
    'Technical Help',
    'Medical Help',
    'Fire',
    'Fleet Help',
  ];
  final Set<String> selectedOptions = {};
  bool _isSending = false;

  void toggleSelection(String option) {
    setState(() {
      if (selectedOptions.contains(option)) {
        selectedOptions.remove(option);
      } else {
        selectedOptions.add(option);
      }
    });
  }

  Future<void> sendSOSNotification() async {
    if (selectedOptions.isEmpty) {
      _showErrorSnackBar('Please select at least one type of help needed.');
      return;
    }

    final accessToken =
        Supabase.instance.client.auth.currentSession?.accessToken;
    if (accessToken == null) {
      _showErrorSnackBar(
          'Authentication error. Please log out and log in again.');
      return;
    }

    setState(() => _isSending = true);

    try {
      //final ownerId = widget.ownerId;
      final agentId = widget.agentId;
      final sosData = {
        'helpOptions': selectedOptions.toList(),
        'message': messageController.text,
      };
      final url =
          'https://rfbodmmhqkvqbufsbfnx.supabase.co/functions/v1/send-sos-notification';
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        // body: jsonEncode({'ownerId': ownerId, 'sosData': sosData}),
        body: jsonEncode({'agentId': agentId, 'sosData': sosData}),

      );

      if (response.statusCode == 200) {
        final responseBody = jsonDecode(response.body);
        // OneSignal can return a 200 but still have an error in the body
        if (responseBody['errors'] != null &&
            responseBody['errors']['invalid_player_ids'] != null) {
          _showErrorSnackBar(
              'Could not send SOS. The owner may need to update their notification settings.');
        } else {
          _showSuccessSnackBar('SOS sent successfully!');
          if (mounted) Navigator.of(context).pop();
        }
      } else {
        final errorBody = jsonDecode(response.body);
        _showErrorSnackBar('Failed to send SOS: ${errorBody['error']}');
      }
    } catch (e) {
      _showErrorSnackBar('An unexpected error occurred: $e');
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool showMessageBox = selectedOptions.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency'),
        centerTitle: true,
        backgroundColor: Colors.teal,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Choose Emergency Type',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal,
                ),
              ),
              const SizedBox(height: 16),
              _buildHelpButtonsGrid(),
              const SizedBox(height: 16),
              if (showMessageBox)
                TextField(
                  controller: messageController,
                  decoration: InputDecoration(
                    labelText: 'Message for Agent',
                    hintText: 'Describe the issue...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.teal),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  maxLines: 3,
                ),
              if (showMessageBox) const SizedBox(height: 20),
              if (showMessageBox) _buildSubmitButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHelpButtonsGrid() {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.1,
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      children: helpOptions.map(_buildGridHelpButton).toList(),
    );
  }

  Widget _buildGridHelpButton(String label) {
    final bool isSelected = selectedOptions.contains(label);
    IconData icon;
    List<Color> gradientColors;

    switch (label) {
      case 'Technical Help':
        icon = Icons.build;
        gradientColors = [Colors.blueAccent, Colors.indigo];
        break;
      case 'Medical Help':
        icon = Icons.local_hospital;
        gradientColors = [Colors.redAccent, Colors.red.shade700];
        break;
      case 'Fire':
        icon = Icons.local_fire_department;
        gradientColors = [Colors.orangeAccent, Colors.deepOrange];
        break;
      case 'Fleet Help':
        icon = Icons.local_shipping;
        gradientColors = [Colors.green, Colors.teal];
        break;
      default:
        icon = Icons.help;
        gradientColors = [Colors.grey.shade400, Colors.grey.shade600];
    }

    return GestureDetector(
      onTap: () => toggleSelection(label),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                offset: const Offset(0, 4),
                blurRadius: 6,
              )
          ],
          border: isSelected
              ? Border.all(color: Colors.black87, width: 3)
              : Border.all(color: Colors.transparent),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 40,
              color: Colors.white,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6.0),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return GestureDetector(
      onTap: _isSending ? null : sendSOSNotification,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: _isSending ? Colors.grey : Colors.teal,
          boxShadow: [
            BoxShadow(
              color: Colors.teal.withValues(alpha: 0.3),
              offset: const Offset(0, 3),
              blurRadius: 6,
            )
          ],
        ),
        child: Center(
          child: _isSending
              ? const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
                color: Colors.white, strokeWidth: 3),
          )
              : const Text(
            'Call The Agent',
            style: TextStyle(
              fontSize: 18,
              color: Colors.white,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}